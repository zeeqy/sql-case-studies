-- Case 3: Foodie-Fi. My own solutions (PostgreSQL 16).
-- Tables: plans(plan_id, plan_name, price), subscriptions(customer_id, plan_id, start_date)
-- Every customer starts on a 7-day free trial (plan 0). Plan 4 = churn.
SET search_path = foodie_fi;

-- =====================================================================
-- A. Customer journey: the 8 sample customers
-- =====================================================================
-- LAG gives the days since the previous plan change, so each journey reads in one line.
SELECT s.customer_id, p.plan_name, s.start_date,
       s.start_date - LAG(s.start_date) OVER (PARTITION BY s.customer_id ORDER BY s.start_date)
           AS days_since_prev
FROM subscriptions s
JOIN plans p USING (plan_id)
WHERE s.customer_id IN (1, 2, 11, 13, 15, 16, 18, 19)
ORDER BY s.customer_id, s.start_date;

-- =====================================================================
-- B. Data analysis
-- =====================================================================

-- B1. Customers ever.
SELECT COUNT(DISTINCT customer_id) AS customers FROM subscriptions;

-- B2. Trial starts per month (grouped by the first day of the month).
SELECT DATE_TRUNC('month', start_date)::DATE AS month, COUNT(*) AS trials
FROM subscriptions
WHERE plan_id = 0
GROUP BY month
ORDER BY month;

-- B3. Plan events starting after 2020, by plan.
SELECT p.plan_name, COUNT(*) AS events_2021
FROM subscriptions s
JOIN plans p USING (plan_id)
WHERE s.start_date >= DATE '2021-01-01'
GROUP BY p.plan_id, p.plan_name
ORDER BY p.plan_id;

-- B4. Customers who have churned, as a count and a share of all customers.
SELECT COUNT(DISTINCT customer_id) FILTER (WHERE plan_id = 4) AS churned,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE plan_id = 4)
             / COUNT(DISTINCT customer_id), 1) AS churn_pct
FROM subscriptions;

-- B5. Customers who churned straight after the free trial.
-- LEAD looks at each customer's next plan. Trial followed directly by churn = churned after trial.
WITH nxt AS (
    SELECT customer_id, plan_id,
           LEAD(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan
    FROM subscriptions
)
SELECT COUNT(*) AS churned_after_trial,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions))
           AS pct
FROM nxt
WHERE plan_id = 0 AND next_plan = 4;

-- B6. What customers chose right after the trial, as counts and shares.
WITH nxt AS (
    SELECT customer_id, plan_id,
           LEAD(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan
    FROM subscriptions
)
SELECT p.plan_name AS after_trial, COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM nxt
JOIN plans p ON p.plan_id = nxt.next_plan
WHERE nxt.plan_id = 0
GROUP BY p.plan_id, p.plan_name
ORDER BY p.plan_id;

-- B7. Each customer's plan on 2020-12-31: their latest plan that started on or before that date.
-- DISTINCT ON keeps the first row per customer under the ORDER BY. Here that is the latest start.
WITH snapshot AS (
    SELECT DISTINCT ON (customer_id) customer_id, plan_id
    FROM subscriptions
    WHERE start_date <= DATE '2020-12-31'
    ORDER BY customer_id, start_date DESC
)
SELECT p.plan_name, COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM snapshot
JOIN plans p USING (plan_id)
GROUP BY p.plan_id, p.plan_name
ORDER BY p.plan_id;

-- B8. Customers who moved to the annual plan during 2020.
SELECT COUNT(DISTINCT customer_id) AS annual_upgrades_2020
FROM subscriptions
WHERE plan_id = 3 AND start_date BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

-- B9. Average days from joining (trial start) to the annual plan.
WITH t AS (
    SELECT customer_id,
           MIN(start_date) FILTER (WHERE plan_id = 0) AS joined,
           MIN(start_date) FILTER (WHERE plan_id = 3) AS annual
    FROM subscriptions
    GROUP BY customer_id
)
SELECT COUNT(*) AS customers, ROUND(AVG(annual - joined)) AS avg_days_to_annual
FROM t
WHERE annual IS NOT NULL;

-- B10. The same, split into 30-day buckets (0-30, 31-60, ...).
-- (days - 1) / 30 puts day 30 in the first bucket and day 31 in the second, matching the labels.
WITH t AS (
    SELECT customer_id,
           MIN(start_date) FILTER (WHERE plan_id = 3) - MIN(start_date) FILTER (WHERE plan_id = 0)
               AS days
    FROM subscriptions
    GROUP BY customer_id
),
b AS (
    SELECT GREATEST(days - 1, 0) / 30 AS bucket FROM t WHERE days IS NOT NULL
)
SELECT CASE WHEN bucket = 0 THEN '0-30'
            ELSE (bucket * 30 + 1) || '-' || (bucket + 1) * 30 END AS days_to_annual,
       COUNT(*) AS customers
FROM b
GROUP BY bucket
ORDER BY bucket;

-- B11. Downgrades from pro monthly straight to basic monthly in 2020.
WITH nxt AS (
    SELECT customer_id, plan_id,
           LEAD(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan,
           LEAD(start_date) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_start
    FROM subscriptions
)
SELECT COUNT(*) AS downgrades_2020
FROM nxt
WHERE plan_id = 2 AND next_plan = 1 AND next_start <= DATE '2020-12-31';

-- =====================================================================
-- C. Payments table for 2020
-- =====================================================================
-- Rules from the brief:
--   * monthly plans bill on the same day of month as the plan's start_date
--   * basic -> pro (monthly or annual) starts at once; the first pro charge is reduced by
--     what was already paid for the current basic month
--   * pro monthly -> pro annual is charged at the end of the current monthly period
--   * no payments after churn
-- My assumption where the brief is silent: a downgrade (e.g. pro -> basic) starts on its own
-- start_date with no refund.
--
-- Note on dates: start_date + n * INTERVAL '1 month' always counts from the original date.
-- generate_series stepping a date by '1 month' adds one month at a time, so 31 Jan -> 29 Feb
-- -> 29 Mar drifts. A series of month numbers avoids that.
DROP TABLE IF EXISTS payments_2020;
CREATE TABLE payments_2020 AS
WITH subs AS (
    SELECT s.customer_id, s.plan_id, p.plan_name, p.price, s.start_date,
           LAG(s.plan_id)     OVER w AS prev_plan,
           LAG(s.start_date)  OVER w AS prev_start,
           LEAD(s.start_date) OVER w AS next_start
    FROM subscriptions s
    JOIN plans p USING (plan_id)
    WHERE s.start_date <= DATE '2020-12-31'
    WINDOW w AS (PARTITION BY s.customer_id ORDER BY s.start_date)
),
monthly AS (
    -- one row per billing date while the monthly plan is active and still in 2020
    SELECT s.customer_id, s.plan_id, s.plan_name, s.prev_plan,
           (s.start_date + n * INTERVAL '1 month')::DATE AS payment_date, s.price
    FROM subs s
    CROSS JOIN LATERAL generate_series(0, 12) AS n
    WHERE s.plan_id IN (1, 2)
      AND (s.start_date + n * INTERVAL '1 month')::DATE < COALESCE(s.next_start, DATE '2021-01-01')
),
annual AS (
    -- from pro monthly: wait for the next monthly billing date on or after the switch
    SELECT s.customer_id, s.plan_id, s.plan_name, s.prev_plan,
           CASE WHEN s.prev_plan = 2 THEN
                (SELECT MIN((s.prev_start + k * INTERVAL '1 month')::DATE)
                 FROM generate_series(0, 24) AS k
                 WHERE (s.prev_start + k * INTERVAL '1 month')::DATE >= s.start_date)
                ELSE s.start_date END AS payment_date,
           s.price
    FROM subs s
    WHERE s.plan_id = 3
),
all_payments AS (
    SELECT * FROM monthly
    UNION ALL
    SELECT * FROM annual
)
SELECT customer_id, plan_id, plan_name, payment_date,
       -- first charge after a basic -> pro upgrade is reduced by the basic fee already paid
       CASE WHEN prev_plan = 1 AND plan_id IN (2, 3)
                 AND payment_date = MIN(payment_date) OVER (PARTITION BY customer_id, plan_id)
            THEN price - 9.90
            ELSE price END AS amount,
       ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY payment_date) AS payment_order
FROM all_payments
WHERE payment_date <= DATE '2020-12-31';

-- Check against the sample customers.
SELECT * FROM payments_2020
WHERE customer_id IN (1, 2, 13, 15, 16, 18, 19)
ORDER BY customer_id, payment_order;

-- C2. Headline numbers from the new table.
SELECT COUNT(*) AS payments, COUNT(DISTINCT customer_id) AS paying_customers,
       SUM(amount) AS revenue_2020
FROM payments_2020;

-- =====================================================================
-- D. Beyond the brief: monthly growth view
-- =====================================================================
-- New paying customers (first paid plan) vs churns per month, and the net change.
WITH first_paid AS (
    SELECT customer_id, MIN(start_date) AS d
    FROM subscriptions WHERE plan_id IN (1, 2, 3) GROUP BY customer_id
),
churns AS (
    SELECT customer_id, start_date AS d FROM subscriptions WHERE plan_id = 4
),
months AS (
    SELECT DATE_TRUNC('month', d)::DATE AS month, 1 AS new_paid, 0 AS churned FROM first_paid
    UNION ALL
    SELECT DATE_TRUNC('month', d)::DATE, 0, 1 FROM churns
)
SELECT month, SUM(new_paid) AS new_paid, SUM(churned) AS churned,
       SUM(new_paid) - SUM(churned) AS net,
       SUM(SUM(new_paid) - SUM(churned)) OVER (ORDER BY month) AS running_net
FROM months
WHERE month <= DATE '2020-12-01'
GROUP BY month
ORDER BY month;
