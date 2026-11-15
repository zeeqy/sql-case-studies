-- Q2. New signups per month, running total, and share completing full KYC.
-- Aggregate first in a CTE, then window over the result. A window inside a GROUP BY query
-- can only use grouped columns, so the CTE keeps it simple.
SET search_path = ewallet;

WITH monthly AS (
    SELECT DATE_TRUNC('month', signup_ts)::DATE AS month,
           COUNT(*) AS signups,
           AVG((kyc_level = 'full')::INT) AS full_kyc_share
    FROM users
    GROUP BY 1
)
SELECT month, signups,
       SUM(signups) OVER (ORDER BY month) AS total_users,
       ROUND(100 * full_kyc_share, 1) AS full_kyc_pct
FROM monthly
ORDER BY month;
