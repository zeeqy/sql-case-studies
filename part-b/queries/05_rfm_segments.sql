-- Q5. RFM segmentation as of 31 Dec 2025, using the last 12 months of activity.
-- R = days since last activity, F = number of activities, M = MYR spent (merchant + bill).
-- NTILE(5) scores each from 1 (worst) to 5 (best); segments are named from the scores.
SET search_path = ewallet;

WITH base AS (
    SELECT wallet_id,
           DATE '2025-12-31' - MAX(txn_date) AS recency_days,
           COUNT(*) AS frequency,
           COALESCE(SUM(amount) FILTER (WHERE txn_type IN ('merchant', 'bill')), 0) AS monetary
    FROM v_activity
    WHERE txn_date > DATE '2025-12-31' - 365
    GROUP BY wallet_id
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r,  -- more recent = higher score
           NTILE(5) OVER (ORDER BY frequency)         AS f,
           NTILE(5) OVER (ORDER BY monetary)          AS m
    FROM base
),
segmented AS (
    SELECT *,
           CASE
               WHEN r >= 4 AND f >= 4 AND m >= 4 THEN '1 Champions'
               WHEN r >= 3 AND f >= 3            THEN '2 Loyal'
               WHEN r >= 4 AND f <= 2            THEN '3 New or promising'
               WHEN r <= 2 AND f >= 3            THEN '4 At risk'
               WHEN r <= 2 AND f <= 2            THEN '6 Hibernating'
               ELSE                                   '5 Needs attention'
           END AS segment
    FROM scored
)
SELECT segment, COUNT(*) AS wallets,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_wallets,
       ROUND(AVG(recency_days)) AS avg_recency_days,
       ROUND(AVG(frequency), 1) AS avg_frequency,
       ROUND(AVG(monetary)) AS avg_spend_myr,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_spend
FROM segmented
GROUP BY segment
ORDER BY segment;
