-- Q11. Fraud-lite: wallets that look like money mules.
-- Pattern: many people send round amounts in a short burst, then the money is quickly
-- passed on. Each signal alone is weak (about half of normal P2P is round, and group
-- collections such as shared meals or a kutu also create bursts), so a burst counts only
-- when ALL of these hold:
--   * 5+ inbound transfers from 5+ different senders, each within 30 min of the previous one
--   * 80%+ of them are round amounts (multiples of RM10)
--   * the wallet sends out 70%+ of the burst total within 30 minutes of the burst ending
-- Burst detection (gaps-and-islands) lives in views.sql, v_p2p_bursts.
-- How well this does against the planted truth: eval/fraud_eval.sql.
SET search_path = ewallet;

SELECT wallet_id,
       COUNT(*) AS suspicious_bursts,
       SUM(transfers_in) AS transfers_in,
       ROUND(SUM(amount_in)) AS amount_in_myr,
       ROUND(100 * SUM(amount_out) / SUM(amount_in)) AS passed_on_pct,
       MIN(burst_start) AS first_seen,
       MAX(burst_end) AS last_seen
FROM v_p2p_bursts
WHERE round_share >= 0.8
  AND amount_out >= 0.7 * amount_in
GROUP BY wallet_id
ORDER BY amount_in_myr DESC, wallet_id;
