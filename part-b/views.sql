-- Part B shared views. Created by `sqlcases seed` after the data load.
-- Queries in part-b/queries build on these, so each business rule lives in one place.
SET search_path = ewallet;

-- "Activity" = something the user chose to do: pay a merchant, pay a bill or send money.
-- Top-ups are excluded on purpose. A wallet that only reloads is not really using the product.
CREATE OR REPLACE VIEW v_activity AS
SELECT txn_id, wallet_id, txn_ts, txn_ts::DATE AS txn_date,
       DATE_TRUNC('month', txn_ts)::DATE AS month, txn_type, amount
FROM transactions
WHERE status = 'success' AND txn_type <> 'topup';

-- Successful merchant payments with category and merchant location.
CREATE OR REPLACE VIEW v_merchant_txn AS
SELECT t.txn_id, t.wallet_id, t.txn_ts, t.txn_ts::DATE AS txn_date,
       DATE_TRUNC('month', t.txn_ts)::DATE AS month, t.amount, t.cashback, t.promo_id,
       t.channel, m.merchant_id, m.merchant_name, m.mcc, m.category, m.state AS merchant_state
FROM transactions t
JOIN merchants m USING (merchant_id)
WHERE t.txn_type = 'merchant' AND t.status = 'success';

-- Promotion effect, measured three ways (see part-b/README.md for why):
--   naive_ratio      eligible daily GMV in the window vs the 28 days before
--   per_user_ratio   same, per registered wallet (removes user growth)
--   did_ratio        difference-in-differences: eligible vs NON-eligible categories over the
--                    same two periods. NULL for all-category promos, which have no control group.
CREATE OR REPLACE VIEW v_promo_effect AS
WITH spend AS (
    SELECT p.promo_id,
           SUM(t.amount) FILTER (WHERE t.txn_date >= p.start_date AND e.eligible)     AS elig_in,
           SUM(t.amount) FILTER (WHERE t.txn_date <  p.start_date AND e.eligible)     AS elig_pre,
           SUM(t.amount) FILTER (WHERE t.txn_date >= p.start_date AND NOT e.eligible) AS ctrl_in,
           SUM(t.amount) FILTER (WHERE t.txn_date <  p.start_date AND NOT e.eligible) AS ctrl_pre
    FROM promotions p
    JOIN v_merchant_txn t ON t.txn_date BETWEEN p.start_date - 28 AND p.end_date
    CROSS JOIN LATERAL (
        SELECT p.eligible_mcc IS NULL OR t.mcc = ANY (p.eligible_mcc) AS eligible) e
    GROUP BY p.promo_id
),
registered AS (  -- average number of wallets that existed on each day of each period
    SELECT p.promo_id,
           AVG(r.n) FILTER (WHERE d.day >= p.start_date) AS reg_in,
           AVG(r.n) FILTER (WHERE d.day <  p.start_date) AS reg_pre
    FROM promotions p
    -- integer day offsets keep this a DATE (a date + interval series would give timestamptz)
    CROSS JOIN LATERAL (SELECT p.start_date + k AS day
                        FROM generate_series(-28, p.end_date - p.start_date) AS k) d
    CROSS JOIN LATERAL (SELECT COUNT(*) AS n FROM wallets w WHERE w.created_ts < d.day + 1) r
    GROUP BY p.promo_id
)
SELECT p.promo_id, p.promo_name, p.start_date, p.end_date,
       p.end_date - p.start_date + 1 AS days,
       s.elig_in, s.elig_pre,
       (s.elig_in / (p.end_date - p.start_date + 1)) / (s.elig_pre / 28)        AS naive_ratio,
       (s.elig_in / (p.end_date - p.start_date + 1) / r.reg_in)
           / (s.elig_pre / 28 / r.reg_pre)                                      AS per_user_ratio,
       CASE WHEN p.eligible_mcc IS NOT NULL
            THEN (s.elig_in / s.elig_pre) / (s.ctrl_in / s.ctrl_pre) END       AS did_ratio
FROM promotions p
JOIN spend s USING (promo_id)
JOIN registered r USING (promo_id);

-- Inbound P2P "bursts": transfers to one wallet, each within 30 minutes of the previous one
-- (gaps-and-islands). For each burst: size, distinct senders, round-amount share, and how
-- much the wallet sent out from the burst start until 30 minutes after it ended.
-- Used by queries/11 (fraud-lite) and eval/fraud_eval.sql.
CREATE OR REPLACE VIEW v_p2p_bursts AS
WITH inbound AS (
    SELECT counterparty_wallet_id AS wallet_id, wallet_id AS sender, txn_ts, amount,
           CASE WHEN txn_ts - LAG(txn_ts) OVER w <= INTERVAL '30 minutes' THEN 0 ELSE 1 END
               AS new_burst
    FROM transactions
    WHERE txn_type = 'p2p' AND status = 'success'
    WINDOW w AS (PARTITION BY counterparty_wallet_id ORDER BY txn_ts)
),
numbered AS (
    SELECT *, SUM(new_burst) OVER (PARTITION BY wallet_id ORDER BY txn_ts) AS burst_no
    FROM inbound
),
bursts AS (
    SELECT wallet_id, burst_no,
           MIN(txn_ts) AS burst_start, MAX(txn_ts) AS burst_end,
           COUNT(*) AS transfers_in, COUNT(DISTINCT sender) AS senders,
           SUM(amount) AS amount_in,
           AVG((amount % 10 = 0)::INT) AS round_share
    FROM numbered
    GROUP BY wallet_id, burst_no
    HAVING COUNT(*) >= 5 AND COUNT(DISTINCT sender) >= 5
)
SELECT b.*,
       (SELECT COALESCE(SUM(o.amount), 0)
        FROM transactions o
        WHERE o.wallet_id = b.wallet_id AND o.txn_type = 'p2p' AND o.status = 'success'
          AND o.txn_ts BETWEEN b.burst_start AND b.burst_end + INTERVAL '30 minutes')
           AS amount_out
FROM bursts b;
