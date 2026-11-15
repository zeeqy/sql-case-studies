"""Part B data loads into Postgres with every constraint satisfied."""

from conftest import needs_db

pytestmark = needs_db


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
