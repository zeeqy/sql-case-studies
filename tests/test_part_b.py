"""Part B data loads into Postgres with every constraint satisfied."""

import pytest
from conftest import needs_db

from sqlcases import db

pytestmark = needs_db


def last_result(conn, sql):
    """Run a multi-statement file and return the rows of its LAST statement.

    psycopg exposes one result set per statement; nextset() steps to the next one.
    """
    cur = conn.execute(sql)
    while cur.nextset():
        pass
    return cur.fetchall()


def scalar(conn, sql):
    return conn.execute(sql).fetchone()[0]


def test_ewallet_loaded(seeded_conn):
    c = seeded_conn
    assert scalar(c, "SELECT COUNT(*) FROM ewallet.users") == 8000
    assert scalar(c, "SELECT COUNT(*) FROM ewallet.wallets") == 8000
    assert scalar(c, "SELECT COUNT(*) FROM ewallet.transactions") > 300_000
    assert scalar(c, "SELECT COUNT(DISTINCT txn_type) FROM ewallet.transactions") == 4


def test_ground_truth_is_separate(seeded_conn):
    # analysis tables must not leak which wallets are mules
    cols = scalar(
        seeded_conn,
        """SELECT COUNT(*) FROM information_schema.columns
           WHERE table_schema = 'ewallet' AND column_name ILIKE '%mule%'""",
    )
    assert cols == 0
    assert scalar(seeded_conn, "SELECT COUNT(*) FROM ewallet_truth.mule_bursts") > 0


QUERIES = sorted((db.ROOT / "part-b" / "queries").glob("*.sql"))


def test_at_least_15_business_questions():
    assert len(QUERIES) >= 15


@pytest.mark.parametrize("path", QUERIES, ids=lambda p: p.stem)
def test_query_runs_and_returns_rows(seeded_conn, path):
    # run the whole file; the last statement is the SELECT
    rows = last_result(seeded_conn, path.read_text(encoding="utf-8"))
    assert rows, f"{path.name} returned no rows"


def test_fraud_rule_beats_naive_rule(seeded_conn):
    sql = (db.ROOT / "part-b" / "eval" / "fraud_eval.sql").read_text(encoding="utf-8")
    rows = {r[0]: r for r in last_result(seeded_conn, sql)}
    naive = next(v for k, v in rows.items() if k.startswith("naive"))
    full = next(v for k, v in rows.items() if k.startswith("full"))
    # columns: rule, flagged, found, planted, precision_pct, recall_pct
    assert full[4] >= 90 and full[5] >= 90
    assert naive[4] < 50  # decoys make the naive rule mostly false alarms


def test_did_is_closer_to_truth_than_naive(seeded_conn):
    rows = seeded_conn.execute(
        """SELECT e.promo_name, e.naive_ratio, e.did_ratio, t.true_uplift
           FROM ewallet.v_promo_effect e
           JOIN ewallet_truth.promo_uplift t USING (promo_id)
           WHERE e.did_ratio IS NOT NULL"""
    ).fetchall()
    assert len(rows) == 4
    # Honest bar: DiD wins on most promos and on average. It is not perfect: on the 5-day
    # 11.11 sale (few, high-ticket purchases) it underestimates. See part-b/README.md.
    wins = sum(abs(did - truth) < abs(naive - truth) for _, naive, did, truth in rows)
    assert wins >= 3
    mae_did = sum(abs(did - truth) for _, _, did, truth in rows) / 4
    mae_naive = sum(abs(naive - truth) for _, naive, _, truth in rows) / 4
    assert mae_did < mae_naive
