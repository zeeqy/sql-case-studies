-- Part B indexes. Applied by `sqlcases seed` after loading. `sqlcases explain` drops them,
-- times the demo queries, re-creates them and times again (see part-b/explain/).
SET search_path = ewallet;

-- Wallet statement / per-wallet history: equality on wallet_id, then a time range.
-- Column order matters: the equality column comes first, the range column second.
CREATE INDEX IF NOT EXISTS ix_txn_wallet_ts ON transactions (wallet_id, txn_ts);

-- Money received. Only P2P rows have a counterparty, so a PARTIAL index skips the ~80%
-- of rows where it is NULL and stays small.
CREATE INDEX IF NOT EXISTS ix_txn_counterparty_ts ON transactions (counterparty_wallet_id, txn_ts)
    WHERE counterparty_wallet_id IS NOT NULL;

-- Merchant drill-downs.
CREATE INDEX IF NOT EXISTS ix_txn_merchant ON transactions (merchant_id)
    WHERE merchant_id IS NOT NULL;

-- Time-range scans. Rows are inserted in time order, so a BRIN index (min/max per block
-- range) is tiny and still lets Postgres skip most of the table for "last N days" queries.
CREATE INDEX IF NOT EXISTS ix_txn_ts_brin ON transactions USING brin (txn_ts);

ANALYZE transactions;
