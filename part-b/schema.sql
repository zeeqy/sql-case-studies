-- Part B: synthetic Malaysian e-wallet ("DompetKu"). Tables only; rows are loaded by
-- `sqlcases seed`, which runs the seeded Python generator (src/sqlcases/generator).
-- Only primary keys and foreign keys here. Analysis indexes live in indexes.sql, so the
-- EXPLAIN ANALYZE before/after comparison in Part B starts from a fair baseline.
-- All timestamps are Malaysia local time (MYT, UTC+8), stored without a time zone.
DROP SCHEMA IF EXISTS ewallet CASCADE;
DROP SCHEMA IF EXISTS ewallet_truth CASCADE;
CREATE SCHEMA ewallet;
SET search_path = ewallet;

CREATE TABLE users (
    user_id     INTEGER PRIMARY KEY,
    full_name   TEXT NOT NULL,             -- synthetic, built from common name parts
    state       TEXT NOT NULL,             -- one of 16 Malaysian states / federal territories
    age_band    TEXT NOT NULL CHECK (age_band IN ('18-24', '25-34', '35-44', '45-54', '55+')),
    kyc_level   TEXT NOT NULL CHECK (kyc_level IN ('basic', 'full')),
    signup_ts   TIMESTAMP NOT NULL
);

CREATE TABLE wallets (
    wallet_id   INTEGER PRIMARY KEY,
    user_id     INTEGER NOT NULL UNIQUE REFERENCES users (user_id),
    tier        TEXT NOT NULL CHECK (tier IN ('lite', 'premium')),  -- premium needs full KYC
    created_ts  TIMESTAMP NOT NULL
);

CREATE TABLE merchants (
    merchant_id   INTEGER PRIMARY KEY,
    merchant_name TEXT NOT NULL,
    mcc           SMALLINT NOT NULL,       -- ISO 18245 merchant category code
    category      TEXT NOT NULL,
    state         TEXT NOT NULL,
    onboarded_on  DATE NOT NULL
);

CREATE TABLE promotions (
    promo_id      INTEGER PRIMARY KEY,
    promo_name    TEXT NOT NULL,
    start_date    DATE NOT NULL,
    end_date      DATE NOT NULL,           -- inclusive
    eligible_mcc  SMALLINT[],              -- NULL = every merchant category
    cashback_pct  NUMERIC(4, 1) NOT NULL,
    cap_per_txn   NUMERIC(6, 2) NOT NULL,  -- max cashback per transaction, MYR
    budget_myr    NUMERIC(10, 2) NOT NULL
);

CREATE TABLE transactions (
    txn_id                 BIGINT PRIMARY KEY,
    wallet_id              INTEGER NOT NULL REFERENCES wallets (wallet_id),
    txn_ts                 TIMESTAMP NOT NULL,
    txn_type               TEXT NOT NULL CHECK (txn_type IN ('topup', 'p2p', 'merchant', 'bill')),
    amount                 NUMERIC(12, 2) NOT NULL CHECK (amount > 0),  -- MYR, always positive
    status                 TEXT NOT NULL CHECK (status IN ('success', 'failed')),
    channel                TEXT NOT NULL,  -- qr / online / in_app / fpx / card / cash_counter
    merchant_id            INTEGER REFERENCES merchants (merchant_id),      -- merchant only
    counterparty_wallet_id INTEGER REFERENCES wallets (wallet_id),         -- p2p receiver
    bill_category          TEXT,                                          -- bill only
    promo_id               INTEGER REFERENCES promotions (promo_id),
    cashback               NUMERIC(8, 2) NOT NULL DEFAULT 0
);

-- Ground truth for the planted patterns, kept in a SEPARATE schema. Analysis queries must
-- never read it. Tests use it to check that the fraud-lite query finds what was planted.
CREATE SCHEMA ewallet_truth;
CREATE TABLE ewallet_truth.mule_bursts (
    user_id   INTEGER NOT NULL,
    burst_start TIMESTAMP NOT NULL,
    burst_end   TIMESTAMP NOT NULL
);
CREATE TABLE ewallet_truth.promo_uplift (
    promo_id  INTEGER PRIMARY KEY,
    true_uplift NUMERIC(4, 2) NOT NULL     -- multiplier on eligible spend rate during the promo
);
