-- Q14. How do people load money? Top-up source mix and size, and how many top-ups are
-- "just in time" (a payment follows within 30 minutes), by state.
SET search_path = ewallet;

WITH topups AS (
    SELECT t.txn_id, t.wallet_id, t.txn_ts, t.amount, t.channel AS source, u.state,
           EXISTS (SELECT 1 FROM transactions n
                   WHERE n.wallet_id = t.wallet_id AND n.txn_type <> 'topup'
                     AND n.txn_ts > t.txn_ts AND n.txn_ts <= t.txn_ts + INTERVAL '30 minutes')
               AS just_in_time
    FROM transactions t
    JOIN wallets w USING (wallet_id)
    JOIN users u USING (user_id)
    WHERE t.txn_type = 'topup' AND t.status = 'success'
)
SELECT state, COUNT(*) AS topups,
       ROUND(AVG(amount)) AS avg_topup_myr,
       ROUND(100.0 * AVG((source = 'fpx')::INT))          AS fpx_pct,
       ROUND(100.0 * AVG((source = 'card')::INT))         AS card_pct,
       ROUND(100.0 * AVG((source = 'cash_counter')::INT)) AS cash_pct,
       ROUND(100.0 * AVG(just_in_time::INT), 1)           AS just_in_time_pct
FROM topups
GROUP BY state
ORDER BY topups DESC;
