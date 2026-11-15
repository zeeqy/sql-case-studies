-- Q17. Are bill payers more valuable? Users who paid at least one bill vs those who never did:
-- months active, spend per active month, and whether still active in Dec 2025.
-- Careful: this is correlation, not cause (bill payers are more often full-KYC, for one).
SET search_path = ewallet;

WITH per_wallet AS (
    SELECT a.wallet_id,
           BOOL_OR(a.txn_type = 'bill') AS pays_bills,
           COUNT(DISTINCT a.month) AS active_months,
           COALESCE(SUM(a.amount) FILTER (WHERE a.txn_type IN ('merchant', 'bill')), 0) AS spend,
           BOOL_OR(a.month = DATE '2025-12-01') AS active_dec_2025
    FROM v_activity a
    JOIN wallets w USING (wallet_id)
    WHERE w.created_ts < DATE '2025-01-01'  -- everyone gets at least a year
    GROUP BY a.wallet_id
)
SELECT pw.pays_bills, COUNT(*) AS wallets,
       ROUND(100.0 * AVG((u.kyc_level = 'full')::INT)) AS full_kyc_pct,
       ROUND(AVG(pw.active_months), 1) AS avg_active_months,
       ROUND(AVG(pw.spend / pw.active_months)) AS spend_per_active_month,
       ROUND(100.0 * AVG(pw.active_dec_2025::INT), 1) AS still_active_pct
FROM per_wallet pw
JOIN wallets w USING (wallet_id)
JOIN users u USING (user_id)
GROUP BY pw.pays_bills
ORDER BY pw.pays_bills DESC;
