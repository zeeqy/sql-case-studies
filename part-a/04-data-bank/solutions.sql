-- Case 4: Data Bank. My own solutions (PostgreSQL 16).
-- Tables: regions(region_id, region_name)
--         customer_nodes(customer_id, region_id, node_id, start_date, end_date)
--         customer_transactions(customer_id, txn_date, txn_type, txn_amount)
-- Data notes found while profiling (see README):
--   * end_date = 9999-12-31 marks the customer's CURRENT node (500 rows, one per customer).
--   * 607 rows "move" a customer to the node they were already on. These are not real
--     reallocations, so A4/A5 merge them first (gaps-and-islands).
--   * Transactions run 2020-01-01 to 2020-04-28. Deposits add money; purchases and withdrawals take it out.
SET search_path = data_bank;

-- Reusable view: one signed amount per transaction.
CREATE OR REPLACE VIEW v_txn AS
SELECT customer_id, txn_date, txn_type, txn_amount,
       CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END AS signed_amount
FROM customer_transactions;

-- Reusable view: one row per customer per day, 2020-01-01 to 2020-04-30, with the
-- end-of-day balance. Days without transactions carry the previous balance forward,
-- which the "previous 30 days" and "real-time" options need.
CREATE OR REPLACE VIEW v_daily_balance AS
WITH days AS (
    SELECT c.customer_id, d::DATE AS day
    FROM (SELECT DISTINCT customer_id FROM customer_transactions) c
    CROSS JOIN generate_series(DATE '2020-01-01', DATE '2020-04-30', INTERVAL '1 day') AS d
),
daily_net AS (
    SELECT customer_id, txn_date AS day, SUM(signed_amount) AS net
    FROM v_txn GROUP BY customer_id, txn_date
)
SELECT d.customer_id, d.day, COALESCE(n.net, 0) AS net,
       SUM(COALESCE(n.net, 0)) OVER (PARTITION BY d.customer_id ORDER BY d.day) AS balance
FROM days d
LEFT JOIN daily_net n USING (customer_id, day);

-- =====================================================================
-- A. Customer nodes
-- =====================================================================

-- A1. Unique nodes. node_id is reused in every region (1-5 each), so a node is really a
-- (region, node) pair. Both counts are shown.
SELECT COUNT(DISTINCT node_id) AS node_ids,
       COUNT(DISTINCT (region_id, node_id)) AS region_nodes
FROM customer_nodes;

-- A2. Nodes per region.
SELECT r.region_name, COUNT(DISTINCT cn.node_id) AS nodes
FROM customer_nodes cn
JOIN regions r USING (region_id)
GROUP BY r.region_id, r.region_name
ORDER BY r.region_id;

-- A3. Customers per region.
SELECT r.region_name, COUNT(DISTINCT cn.customer_id) AS customers
FROM customer_nodes cn
JOIN regions r USING (region_id)
GROUP BY r.region_id, r.region_name
ORDER BY customers DESC;

-- A4. Average days before a customer is moved to a DIFFERENT node.
-- Step 1 (islands): start a new group whenever the node changes. A running SUM of a
--   "changed" flag gives each unbroken run on one node the same group number.
-- Step 2: collapse each run to one stint and measure it. Current stints (9999) are excluded
--   because they have not ended yet.
-- Days = end_date - start_date + 1, i.e. the days until the next node's start_date.
WITH flagged AS (
    SELECT *,
           CASE WHEN node_id = LAG(node_id) OVER w THEN 0 ELSE 1 END AS new_stint
    FROM customer_nodes
    WINDOW w AS (PARTITION BY customer_id ORDER BY start_date)
),
grouped AS (
    SELECT *, SUM(new_stint) OVER (PARTITION BY customer_id ORDER BY start_date) AS stint_id
    FROM flagged
),
stints AS (
    SELECT customer_id, region_id, stint_id, MIN(start_date) AS s, MAX(end_date) AS e
    FROM grouped
    GROUP BY customer_id, region_id, stint_id
)
SELECT 'merged (real moves)' AS method, ROUND(AVG(e - s + 1), 1) AS avg_days, COUNT(*) AS stints
FROM stints WHERE e <> DATE '9999-12-31'
UNION ALL
SELECT 'naive (every row)', ROUND(AVG(end_date - start_date + 1), 1), COUNT(*)
FROM customer_nodes WHERE end_date <> DATE '9999-12-31';

-- A5. Median, 80th and 95th percentile of the same metric, per region.
-- PERCENTILE_CONT interpolates; it is an ordered-set aggregate (WITHIN GROUP).
WITH flagged AS (
    SELECT *,
           CASE WHEN node_id = LAG(node_id) OVER w THEN 0 ELSE 1 END AS new_stint
    FROM customer_nodes
    WINDOW w AS (PARTITION BY customer_id ORDER BY start_date)
),
grouped AS (
    SELECT *, SUM(new_stint) OVER (PARTITION BY customer_id ORDER BY start_date) AS stint_id
    FROM flagged
),
stints AS (
    SELECT customer_id, region_id, MAX(end_date) - MIN(start_date) + 1 AS days,
           MAX(end_date) AS e
    FROM grouped
    GROUP BY customer_id, region_id, stint_id
)
SELECT r.region_name,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days)::NUMERIC, 1) AS median_days,
       ROUND(PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY days)::NUMERIC, 1) AS p80_days,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY days)::NUMERIC, 1) AS p95_days
FROM stints
JOIN regions r USING (region_id)
WHERE e <> DATE '9999-12-31'
GROUP BY r.region_id, r.region_name
ORDER BY r.region_id;

-- =====================================================================
-- B. Customer transactions
-- =====================================================================

-- B1. Count and total per transaction type.
SELECT txn_type, COUNT(*) AS txns, SUM(txn_amount) AS total_amount
FROM customer_transactions
GROUP BY txn_type
ORDER BY txn_type;

-- B2. Average number of deposits and average deposit total per customer.
SELECT ROUND(AVG(n), 1) AS avg_deposit_count, ROUND(AVG(total), 2) AS avg_deposit_total
FROM (SELECT customer_id, COUNT(*) AS n, SUM(txn_amount) AS total
      FROM customer_transactions WHERE txn_type = 'deposit'
      GROUP BY customer_id) d;

-- B3. Per month: customers with more than 1 deposit AND at least 1 purchase or withdrawal.
-- I read "either 1 purchase or 1 withdrawal" as "at least one of either".
WITH m AS (
    SELECT customer_id, DATE_TRUNC('month', txn_date)::DATE AS month,
           COUNT(*) FILTER (WHERE txn_type = 'deposit') AS deposits,
           COUNT(*) FILTER (WHERE txn_type IN ('purchase', 'withdrawal')) AS outflows
    FROM customer_transactions
    GROUP BY customer_id, month
)
SELECT month, COUNT(*) AS active_customers
FROM m
WHERE deposits > 1 AND outflows >= 1
GROUP BY month
ORDER BY month;

-- B4. Closing balance per customer per month, including months with no transactions.
-- A month spine per customer (CROSS JOIN) stops silent months from disappearing.
-- Shown for the first 3 customers. The full table feeds B5 and C.
CREATE OR REPLACE VIEW v_month_end AS
WITH months AS (
    SELECT c.customer_id, m::DATE AS month
    FROM (SELECT DISTINCT customer_id FROM customer_transactions) c
    CROSS JOIN generate_series(DATE '2020-01-01', DATE '2020-04-01', INTERVAL '1 month') AS m
),
monthly_net AS (
    SELECT customer_id, DATE_TRUNC('month', txn_date)::DATE AS month, SUM(signed_amount) AS net
    FROM v_txn GROUP BY 1, 2
)
SELECT mo.customer_id, mo.month, COALESCE(n.net, 0) AS net_change,
       SUM(COALESCE(n.net, 0)) OVER (PARTITION BY mo.customer_id ORDER BY mo.month)
           AS closing_balance
FROM months mo
LEFT JOIN monthly_net n USING (customer_id, month);

SELECT * FROM v_month_end WHERE customer_id <= 3 ORDER BY customer_id, month;

-- B5. Share of customers whose closing balance grew by more than 5%.
-- The question is ambiguous, so I answer it two ways:
--   (a) April closing vs January closing (overall growth), and
--   (b) customers who had at least one month-over-month increase over 5%.
-- A percentage change is only meaningful from a POSITIVE base. Customers starting at
-- zero or in overdraft are left out of (a) and counted separately.
WITH ends AS (
    SELECT customer_id,
           MAX(closing_balance) FILTER (WHERE month = DATE '2020-01-01') AS jan,
           MAX(closing_balance) FILTER (WHERE month = DATE '2020-04-01') AS apr
    FROM v_month_end GROUP BY customer_id
)
SELECT 'a) Apr vs Jan > +5%' AS measure,
       ROUND(100.0 * COUNT(*) FILTER (WHERE jan > 0 AND apr > jan * 1.05)
             / COUNT(*) FILTER (WHERE jan > 0), 1) AS pct_of_eligible,
       COUNT(*) FILTER (WHERE jan > 0) AS eligible_customers,
       COUNT(*) FILTER (WHERE jan <= 0) AS excluded_non_positive_start
FROM ends
UNION ALL
SELECT 'b) any month > +5% MoM',
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE grew)
             / COUNT(DISTINCT customer_id), 1),
       COUNT(DISTINCT customer_id), NULL
FROM (SELECT customer_id,
             LAG(closing_balance) OVER (PARTITION BY customer_id ORDER BY month) > 0
             AND closing_balance > 1.05 * LAG(closing_balance)
                 OVER (PARTITION BY customer_id ORDER BY month) AS grew
      FROM v_month_end) x;

-- =====================================================================
-- C. Data allocation challenge
-- =====================================================================
-- Data is provisioned in GB at 1 GB per $1 of balance. A negative balance gets 0 data,
-- not "negative data": GREATEST(balance, 0).

-- C1. Running balance after every transaction (shown for customer 1).
-- Ties on the same day: ORDER BY txn_date with the default RANGE frame gives every
-- same-day transaction the same day-end balance. ROWS + a tiebreaker makes each one show
-- its own step.
SELECT customer_id, txn_date, txn_type, signed_amount,
       SUM(signed_amount) OVER (PARTITION BY customer_id
                                ORDER BY txn_date, txn_type, txn_amount
                                ROWS UNBOUNDED PRECEDING) AS running_balance
FROM v_txn
WHERE customer_id = 1
ORDER BY txn_date, txn_type, txn_amount;

-- C2. Min / average / max running balance per customer (first 5 shown).
WITH running AS (
    SELECT customer_id,
           SUM(signed_amount) OVER (PARTITION BY customer_id
                                    ORDER BY txn_date, txn_type, txn_amount
                                    ROWS UNBOUNDED PRECEDING) AS bal
    FROM v_txn
)
SELECT customer_id, MIN(bal) AS min_bal, ROUND(AVG(bal), 1) AS avg_bal, MAX(bal) AS max_bal
FROM running
GROUP BY customer_id
ORDER BY customer_id
LIMIT 5;

-- C3. Data needed per month under each option.
--   Option 1: allocation for month M = previous month's closing balance.
--   Option 2: allocation for month M = average daily balance over the last 30 days of M-1.
--   Option 3: real-time, data always equals the current balance. To provision for it you
--             need the PEAK total of the month (the highest day), not an average.
-- January has no previous month, so options 1 and 2 start in February.
WITH opt1 AS (
    SELECT (month + INTERVAL '1 month')::DATE AS month,
           SUM(GREATEST(closing_balance, 0)) AS gb
    FROM v_month_end
    WHERE month < DATE '2020-04-01'
    GROUP BY month
),
trail30 AS (
    SELECT customer_id, day,
           AVG(balance) OVER (PARTITION BY customer_id ORDER BY day
                              ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS avg30
    FROM v_daily_balance
),
opt2 AS (
    SELECT (DATE_TRUNC('month', day) + INTERVAL '1 month')::DATE AS month,
           ROUND(SUM(GREATEST(avg30, 0))) AS gb
    FROM trail30
    WHERE day = (DATE_TRUNC('month', day) + INTERVAL '1 month - 1 day')::DATE  -- month end
      AND day < DATE '2020-04-30'
    GROUP BY 1
),
opt3 AS (
    SELECT month, MAX(total) AS gb
    FROM (SELECT DATE_TRUNC('month', day)::DATE AS month, day,
                 SUM(GREATEST(balance, 0)) AS total
          FROM v_daily_balance GROUP BY day) d
    GROUP BY month
)
SELECT o3.month, o1.gb AS option1_prev_month_end, o2.gb AS option2_avg_30_days,
       o3.gb AS option3_realtime_peak
FROM opt3 o3
LEFT JOIN opt1 o1 USING (month)
LEFT JOIN opt2 o2 USING (month)
ORDER BY o3.month;

-- =====================================================================
-- D. Extra challenge: 6% a year interest, credited daily as extra data
-- =====================================================================
-- Daily rate = 6% / 365. Interest accrues only on positive balances.

-- D1. Simple interest (no compounding): each day earns rate * that day's balance.
-- Interest is paid into the account (like the compounding version), so later withdrawals
-- can use it; it just never earns interest itself. Monthly data = month-end balance incl. interest.
WITH d AS (
    SELECT customer_id, day, balance,
           SUM(GREATEST(balance, 0) * 0.06 / 365)
               OVER (PARTITION BY customer_id ORDER BY day) AS interest_to_date
    FROM v_daily_balance
)
SELECT DATE_TRUNC('month', day)::DATE AS month,
       ROUND(SUM(GREATEST(balance + interest_to_date, 0))) AS gb_simple,
       ROUND(SUM(interest_to_date), 2) AS of_which_interest
FROM d
WHERE day = (DATE_TRUNC('month', day) + INTERVAL '1 month - 1 day')::DATE
GROUP BY 1
ORDER BY 1;

-- D2. Daily compounding: interest is added to the balance, so tomorrow's interest
-- includes it. Each day depends on the day before, which a window cannot express,
-- so a recursive CTE walks forward one day at a time (500 customers x 121 days).
WITH RECURSIVE base AS (
    SELECT customer_id, day, net, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY day) AS i
    FROM v_daily_balance
),
walk AS (
    SELECT customer_id, i, day,
           CASE WHEN net > 0 THEN net * (1 + 0.06 / 365) ELSE net END::NUMERIC AS bal
    FROM base WHERE i = 1
    UNION ALL
    SELECT b.customer_id, b.i, b.day,
           CASE WHEN w.bal + b.net > 0 THEN (w.bal + b.net) * (1 + 0.06 / 365)
                ELSE w.bal + b.net END
    FROM walk w
    JOIN base b ON b.customer_id = w.customer_id AND b.i = w.i + 1
)
SELECT DATE_TRUNC('month', day)::DATE AS month, ROUND(SUM(GREATEST(bal, 0))) AS gb_compound
FROM walk
WHERE day = (DATE_TRUNC('month', day) + INTERVAL '1 month - 1 day')::DATE
GROUP BY 1
ORDER BY 1;
