-- Queries timed by `sqlcases explain`, without and then with part-b/indexes.sql.
-- Each block starts with "-- name:" and holds one statement.

-- name: wallet_statement
-- A customer opens their Q4 2025 statement: money out AND money in for one wallet.
-- Expect: sequential scan of every row before; BitmapOr of two index scans after.
SELECT txn_id, txn_ts, txn_type, amount, status
FROM ewallet.transactions
WHERE (wallet_id = 102101 OR counterparty_wallet_id = 102101)
  AND txn_ts >= '2025-10-01' AND txn_ts < '2026-01-01'
ORDER BY txn_ts;

-- name: last_7_days_by_category
-- Ops dashboard: merchant GMV by category over the last 7 days of data.
-- Expect: the BRIN index lets Postgres read only the last few block ranges.
SELECT m.category, COUNT(*) AS txns, SUM(t.amount) AS gmv
FROM ewallet.transactions t
JOIN ewallet.merchants m USING (merchant_id)
WHERE t.txn_type = 'merchant' AND t.status = 'success'
  AND t.txn_ts >= '2025-12-25'
GROUP BY m.category;

-- name: full_history_by_category
-- Counter-example: GMV by category over ALL time. This reads most of the table either way,
-- so a sequential scan stays the best plan and the indexes should NOT help.
SELECT m.category, SUM(t.amount) AS gmv
FROM ewallet.transactions t
JOIN ewallet.merchants m USING (merchant_id)
WHERE t.txn_type = 'merchant' AND t.status = 'success'
GROUP BY m.category;
