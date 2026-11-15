-- Evaluation ONLY: this file reads the planted ground truth (ewallet_truth), which a real
-- analyst would not have. It scores the fraud-lite rule (queries/11) against a naive rule.
--   precision = flagged wallets that really are mules / all flagged wallets
--   recall    = mules that were flagged / all mules
SET search_path = ewallet;

WITH truth AS (
    SELECT DISTINCT user_id + 100000 AS wallet_id FROM ewallet_truth.mule_bursts
),
rules AS (
    SELECT 'naive: burst of 5+ round transfers' AS rule, wallet_id
    FROM v_p2p_bursts WHERE round_share >= 0.8
    UNION
    SELECT 'full: burst + 70% passed on within 30 min', wallet_id
    FROM v_p2p_bursts WHERE round_share >= 0.8 AND amount_out >= 0.7 * amount_in
)
SELECT r.rule,
       COUNT(DISTINCT r.wallet_id) AS flagged,
       COUNT(DISTINCT r.wallet_id) FILTER (WHERE t.wallet_id IS NOT NULL) AS true_mules_found,
       (SELECT COUNT(*) FROM truth) AS mules_planted,
       ROUND(100.0 * COUNT(DISTINCT r.wallet_id) FILTER (WHERE t.wallet_id IS NOT NULL)
             / COUNT(DISTINCT r.wallet_id)) AS precision_pct,
       ROUND(100.0 * COUNT(DISTINCT r.wallet_id) FILTER (WHERE t.wallet_id IS NOT NULL)
             / (SELECT COUNT(*) FROM truth)) AS recall_pct
FROM rules r
LEFT JOIN truth t USING (wallet_id)
GROUP BY r.rule
ORDER BY precision_pct;
