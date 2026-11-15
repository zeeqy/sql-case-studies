-- Q10. Cashback campaign ROI.
--   incremental GMV = eligible GMV in the window x (1 - 1 / uplift): spend that would not
--                     have happened without the promo
--   revenue         = incremental GMV x merchant discount rate (MDR). ASSUMPTION: 1.0%
--   leakage         = share of cashback paid on spend that would have happened anyway
-- A negative ROI on MDR alone is normal for wallets: campaigns are bought for acquisition and
-- habit. So the query also shows cost per RM100 of incremental spend and new signups.
SET search_path = ewallet;

WITH cost AS (
    SELECT promo_id, SUM(cashback) AS cashback_paid
    FROM transactions
    WHERE promo_id IS NOT NULL
    GROUP BY promo_id
),
signups AS (
    SELECT p.promo_id, COUNT(u.user_id) AS new_users
    FROM promotions p
    LEFT JOIN users u ON u.signup_ts::DATE BETWEEN p.start_date AND p.end_date
    GROUP BY p.promo_id
),
est AS (
    SELECT e.*, COALESCE(e.did_ratio, e.per_user_ratio) AS uplift,
           e.elig_in * (1 - 1 / COALESCE(e.did_ratio, e.per_user_ratio)) AS incremental
    FROM v_promo_effect e
)
SELECT e.promo_name, p.budget_myr,
       ROUND(c.cashback_paid) AS cashback_paid,
       ROUND(100 * c.cashback_paid / p.budget_myr) AS budget_used_pct,
       ROUND(e.elig_in) AS eligible_gmv,
       ROUND(e.incremental) AS incremental_gmv,
       ROUND(100 / e.uplift) AS leakage_pct,
       ROUND(100 * (e.incremental * 0.01 - c.cashback_paid) / c.cashback_paid) AS roi_on_mdr_pct,
       ROUND(100 * c.cashback_paid / NULLIF(e.incremental, 0), 2) AS cost_per_rm100_incremental,
       s.new_users
FROM est e
JOIN promotions p USING (promo_id)
JOIN cost c USING (promo_id)
JOIN signups s USING (promo_id)
ORDER BY cost_per_rm100_incremental;
