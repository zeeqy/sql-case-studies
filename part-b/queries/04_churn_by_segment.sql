-- Q4. Who has churned? As of 31 Dec 2025, a wallet is churned if its last activity was more than
-- 60 days ago. Broken down by KYC level and by whether the user pays bills in the app.
SET search_path = ewallet;

WITH last_seen AS (
    SELECT w.wallet_id, u.kyc_level,
           MAX(a.txn_date) AS last_active,
           COALESCE(BOOL_OR(a.txn_type = 'bill'), FALSE) AS pays_bills
    FROM wallets w
    JOIN users u USING (user_id)
    LEFT JOIN v_activity a USING (wallet_id)
    WHERE w.created_ts < DATE '2025-11-01'  -- newer wallets are too new to judge
    GROUP BY w.wallet_id, u.kyc_level
)
SELECT kyc_level, pays_bills,
       COUNT(*) AS wallets,
       ROUND(100.0 * AVG((last_active IS NULL OR last_active < DATE '2025-12-31' - 60)::INT), 1)
           AS churned_pct
FROM last_seen
GROUP BY ROLLUP (kyc_level, pays_bills)  -- adds a subtotal per KYC level and a grand total
ORDER BY kyc_level NULLS LAST, pays_bills NULLS LAST;
