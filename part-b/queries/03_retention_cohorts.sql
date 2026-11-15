-- Q3. Retention by signup cohort: % of each month's new users still active N months later.
-- Cells that are not observable yet (cohort + N months is after Dec 2025) are NULL, not 0.
-- Showing 0% there would make recent cohorts look terrible. This "right-censoring" mistake is common.
SET search_path = ewallet;

WITH cohort AS (
    SELECT wallet_id, DATE_TRUNC('month', created_ts)::DATE AS cohort FROM wallets
),
activity AS (SELECT DISTINCT wallet_id, month FROM v_activity),
grid AS (
    SELECT c.cohort, v.n,
           COUNT(DISTINCT c.wallet_id) AS cohort_size,
           COUNT(DISTINCT a.wallet_id) AS retained
    FROM cohort c
    CROSS JOIN (VALUES (0), (1), (2), (3), (6), (9), (12)) AS v(n)
    LEFT JOIN activity a
           ON a.wallet_id = c.wallet_id AND a.month = (c.cohort + v.n * INTERVAL '1 month')::DATE
    GROUP BY c.cohort, v.n
),
pct AS (
    SELECT *,
           CASE WHEN cohort + n * INTERVAL '1 month' <= DATE '2025-12-01'
                THEN ROUND(100.0 * retained / cohort_size) END AS pct
    FROM grid
)
SELECT cohort, MAX(cohort_size) AS users,
       MAX(pct) FILTER (WHERE n = 0)  AS m0,
       MAX(pct) FILTER (WHERE n = 1)  AS m1,
       MAX(pct) FILTER (WHERE n = 2)  AS m2,
       MAX(pct) FILTER (WHERE n = 3)  AS m3,
       MAX(pct) FILTER (WHERE n = 6)  AS m6,
       MAX(pct) FILTER (WHERE n = 9)  AS m9,
       MAX(pct) FILTER (WHERE n = 12) AS m12
FROM pct
GROUP BY cohort
ORDER BY cohort;
