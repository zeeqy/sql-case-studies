-- Q18. The P2P network: how often relationships are two-way (A sent to B and B sent to A),
-- and how much money crosses state lines. Reciprocity signals healthy social use.
-- Mules (Q11) look the opposite: many one-way senders.
SET search_path = ewallet;

WITH p2p AS (
    SELECT t.wallet_id AS sender, t.counterparty_wallet_id AS receiver, t.amount,
           us.state AS from_state, ur.state AS to_state
    FROM transactions t
    JOIN wallets ws ON ws.wallet_id = t.wallet_id
    JOIN users us ON us.user_id = ws.user_id
    JOIN wallets wr ON wr.wallet_id = t.counterparty_wallet_id
    JOIN users ur ON ur.user_id = wr.user_id
    WHERE t.txn_type = 'p2p' AND t.status = 'success'
),
pairs AS (SELECT DISTINCT sender, receiver FROM p2p),
reciprocal AS (  -- a LEFT JOIN anti/semi-join pattern: does the reverse pair exist?
    SELECT p.sender, p.receiver, q.sender IS NOT NULL AS two_way
    FROM pairs p
    LEFT JOIN pairs q ON q.sender = p.receiver AND q.receiver = p.sender
)
SELECT 'two-way pairs (% of sender-receiver pairs)' AS metric,
       ROUND(100.0 * AVG(two_way::INT), 1) AS pct
FROM reciprocal
UNION ALL
SELECT 'cross-state transfers (% of P2P MYR)',
       ROUND(100.0 * SUM(amount) FILTER (WHERE from_state <> to_state) / SUM(amount), 1)
FROM p2p;
