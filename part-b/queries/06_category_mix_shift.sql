-- Q6. How has the spending mix shifted? Each category's share of merchant GMV,
-- first quarter (Q1 2024) vs last quarter (Q4 2025), in percentage points and relative %.
-- Both matter: a cheap category (transit) can grow fast relatively and still move few points.
SET search_path = ewallet;

WITH q AS (
    SELECT category,
           SUM(amount) FILTER (WHERE txn_date <  DATE '2024-04-01') AS gmv_first,
           SUM(amount) FILTER (WHERE txn_date >= DATE '2025-10-01') AS gmv_last
    FROM v_merchant_txn
    GROUP BY category
),
shares AS (
    SELECT category,
           100 * gmv_first / SUM(gmv_first) OVER () AS share_first,
           100 * gmv_last  / SUM(gmv_last)  OVER () AS share_last
    FROM q
)
SELECT category,
       ROUND(share_first, 1) AS share_q1_2024,
       ROUND(share_last, 1)  AS share_q4_2025,
       ROUND(share_last - share_first, 1) AS change_pp,
       ROUND(100 * (share_last / share_first - 1)) AS relative_change_pct
FROM shares
ORDER BY relative_change_pct DESC;
