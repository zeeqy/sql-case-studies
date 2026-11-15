-- Q9. Did each cashback campaign change behaviour? Three estimates of the uplift in eligible
-- spend, from weakest to strongest (logic in views.sql, v_promo_effect):
--   naive     window vs the 28 days before: mixes in user growth and seasonality
--   per_user  same, per registered wallet: removes user growth
--   did       difference-in-differences against non-eligible categories: also removes
--             seasonality and anything else that moves all categories together
-- "best" = DiD where a control group exists, otherwise per-user.
SET search_path = ewallet;

SELECT promo_id, promo_name, start_date, end_date,
       ROUND(naive_ratio, 2)    AS naive,
       ROUND(per_user_ratio, 2) AS per_user,
       ROUND(did_ratio, 2)      AS did,
       ROUND(COALESCE(did_ratio, per_user_ratio), 2) AS best_estimate,
       CASE WHEN did_ratio IS NULL THEN 'per-user (no control group)' ELSE 'DiD' END AS method
FROM v_promo_effect
ORDER BY promo_id;
