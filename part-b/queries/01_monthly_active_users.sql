-- Q1. Monthly active users (MAU), month-on-month growth, and stickiness (DAU / MAU).
-- Active = at least one successful payment, bill or transfer that month (top-ups don't count).
SET search_path = ewallet;

WITH mau AS (
    SELECT month, COUNT(DISTINCT wallet_id) AS mau
    FROM v_activity
    GROUP BY month
),
dau AS (  -- average daily actives within each month
    SELECT DATE_TRUNC('month', txn_date)::DATE AS month, AVG(n) AS avg_dau
    FROM (SELECT txn_date, COUNT(DISTINCT wallet_id) AS n FROM v_activity GROUP BY txn_date) d
    GROUP BY 1
)
SELECT m.month, m.mau,
       ROUND(100.0 * (m.mau - LAG(m.mau) OVER w) / LAG(m.mau) OVER w, 1) AS mom_growth_pct,
       ROUND(d.avg_dau) AS avg_dau,
       ROUND(100.0 * d.avg_dau / m.mau, 1) AS stickiness_pct
FROM mau m
JOIN dau d USING (month)
WINDOW w AS (ORDER BY m.month)
ORDER BY m.month;
