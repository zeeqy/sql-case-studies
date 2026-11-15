-- Q13. Activation funnel: signup -> first top-up -> first payment -> active again the next
-- calendar month. Conversion at each step and median hours to first payment, by KYC level.
SET search_path = ewallet;

WITH firsts AS (
    SELECT w.wallet_id, u.kyc_level, w.created_ts,
           MIN(t.txn_ts) FILTER (WHERE t.txn_type = 'topup' AND t.status = 'success')
               AS first_topup,
           MIN(t.txn_ts) FILTER (WHERE t.txn_type IN ('merchant', 'bill') AND t.status = 'success')
               AS first_payment,
           COALESCE(BOOL_OR(t.status = 'success' AND t.txn_type <> 'topup'
                            AND DATE_TRUNC('month', t.txn_ts)
                                = DATE_TRUNC('month', w.created_ts) + INTERVAL '1 month'), FALSE)
               AS active_next_month
    FROM wallets w
    JOIN users u USING (user_id)
    LEFT JOIN transactions t USING (wallet_id)
    WHERE w.created_ts < DATE '2025-12-01'  -- need a full next month to observe
    GROUP BY w.wallet_id, u.kyc_level, w.created_ts
)
SELECT kyc_level,
       COUNT(*) AS signups,
       ROUND(100.0 * COUNT(first_topup) / COUNT(*), 1)   AS topped_up_pct,
       ROUND(100.0 * COUNT(first_payment) / COUNT(*), 1) AS paid_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE active_next_month) / COUNT(*), 1) AS active_m1_pct,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (
                  ORDER BY EXTRACT(EPOCH FROM first_payment - created_ts) / 3600))::NUMERIC, 1)
           AS median_hours_to_first_payment
FROM firsts
GROUP BY ROLLUP (kyc_level)
ORDER BY kyc_level NULLS LAST;
