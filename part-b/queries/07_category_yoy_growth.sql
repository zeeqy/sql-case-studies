-- Q7. Category growth 2025 vs 2024, split into "more transactions" vs "bigger tickets".
-- GMV growth = (1 + count growth) x (1 + ticket growth) - 1, so the two parts multiply.
SET search_path = ewallet;

WITH y AS (
    SELECT category, EXTRACT(YEAR FROM txn_date)::INT AS yr,
           SUM(amount) AS gmv, COUNT(*) AS txns, AVG(amount) AS avg_ticket
    FROM v_merchant_txn
    GROUP BY category, yr
),
p AS (
    SELECT category,
           MAX(gmv) FILTER (WHERE yr = 2024)  AS gmv_24, MAX(gmv) FILTER (WHERE yr = 2025)  AS gmv_25,
           MAX(txns) FILTER (WHERE yr = 2024) AS n_24,   MAX(txns) FILTER (WHERE yr = 2025) AS n_25,
           MAX(avg_ticket) FILTER (WHERE yr = 2024) AS t_24,
           MAX(avg_ticket) FILTER (WHERE yr = 2025) AS t_25
    FROM y
    GROUP BY category
)
SELECT category, ROUND(gmv_25) AS gmv_2025_myr,
       ROUND(100 * (gmv_25 / gmv_24 - 1), 1) AS gmv_yoy_pct,
       ROUND(100 * (n_25::NUMERIC / n_24 - 1), 1) AS txn_count_yoy_pct,
       ROUND(100 * (t_25 / t_24 - 1), 1) AS avg_ticket_yoy_pct
FROM p
ORDER BY gmv_yoy_pct DESC;
