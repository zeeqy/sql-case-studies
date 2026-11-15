-- Q8. Top 3 merchants per state by 2025 GMV, and their share of the state's merchant GMV.
-- RANK (not ROW_NUMBER) so ties are kept. "National" = ride-hailing and transit operators.
SET search_path = ewallet;

WITH g AS (
    SELECT merchant_state AS state, merchant_name, category, SUM(amount) AS gmv
    FROM v_merchant_txn
    WHERE txn_date >= DATE '2025-01-01'
    GROUP BY merchant_state, merchant_id, merchant_name, category
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY state ORDER BY gmv DESC) AS rnk,
           100 * gmv / SUM(gmv) OVER (PARTITION BY state) AS share,
           SUM(gmv) OVER (PARTITION BY state) AS state_gmv
    FROM g
)
SELECT state, rnk, merchant_name, category, ROUND(gmv) AS gmv_2025_myr,
       ROUND(share, 1) AS pct_of_state
FROM ranked
WHERE rnk <= 3
ORDER BY state_gmv DESC, rnk;
