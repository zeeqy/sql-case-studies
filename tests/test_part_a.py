"""Every Part A solutions.sql must run cleanly on a fresh seed, and key answers must hold."""

from decimal import Decimal

import pytest
from conftest import needs_db

from sqlcases import db

CASES = sorted(p.parent.name for p in db.ROOT.glob("part-a/*/solutions.sql"))

pytestmark = needs_db


def run_case(conn, case):
    db.run_sql_file(conn, db.ROOT / "part-a" / case / "solutions.sql")


def row(conn, sql):
    return conn.execute(sql).fetchone()


def scalar(conn, sql):
    return row(conn, sql)[0]


def test_all_four_cases_present():
    assert CASES == ["01-dannys-diner", "02-pizza-runner", "03-foodie-fi", "04-data-bank"]


@pytest.mark.parametrize("case", CASES)
def test_solutions_run_clean(seeded_conn, case):
    run_case(seeded_conn, case)


def test_seed_row_counts_match_published_datasets(seeded_conn):
    counts = {
        "dannys_diner.sales": 15,
        "pizza_runner.customer_orders": 14,
        "foodie_fi.subscriptions": 2650,
        "data_bank.customer_nodes": 3500,
        "data_bank.customer_transactions": 5868,
    }
    for table, n in counts.items():
        assert scalar(seeded_conn, f"SELECT COUNT(*) FROM {table}") == n, table


def test_pizza_cleaning(seeded_conn):
    c = seeded_conn
    # '', 'null' and NULL all became empty arrays: 7 pizzas have no changes at all
    no_changes = """SELECT COUNT(*) FROM pizza_runner.clean_customer_orders
                    WHERE cardinality(exclusions) = 0 AND cardinality(extras) = 0"""
    assert scalar(c, no_changes) == 7
    # units stripped from text: '20km', '23.4 km', '32 minutes', '15 minute' ...
    totals = "SELECT SUM(distance_km), SUM(duration_min) FROM pizza_runner.clean_runner_orders"
    assert row(c, totals) == (Decimal("145.2"), 184)
    delivered = "SELECT COUNT(*) FROM pizza_runner.clean_runner_orders WHERE cancellation IS NULL"
    assert scalar(c, delivered) == 8


def test_bonus_dml_rolled_back(seeded_conn):
    run_case(seeded_conn, "02-pizza-runner")
    assert scalar(seeded_conn, "SELECT COUNT(*) FROM pizza_runner.pizza_names") == 2


def test_foodie_fi_payments(seeded_conn):
    run_case(seeded_conn, "03-foodie-fi")
    c = seeded_conn
    assert row(c, "SELECT COUNT(*), SUM(amount) FROM foodie_fi.payments_2020") == (
        4446,
        Decimal("100555.00"),
    )
    # basic -> pro annual upgrade is reduced by the basic fee already paid
    upgrade = "SELECT amount FROM foodie_fi.payments_2020 WHERE customer_id = 16 AND plan_id = 3"
    assert scalar(c, upgrade) == Decimal("189.10")
    after_churn = """SELECT COUNT(*) FROM foodie_fi.payments_2020 p
                     JOIN foodie_fi.subscriptions s
                       ON s.customer_id = p.customer_id AND s.plan_id = 4
                     WHERE p.payment_date >= s.start_date"""
    assert scalar(c, after_churn) == 0


def test_data_bank_month_end_spine(seeded_conn):
    run_case(seeded_conn, "04-data-bank")
    c = seeded_conn
    # 500 customers x 4 months, silent months included
    assert scalar(c, "SELECT COUNT(*) FROM data_bank.v_month_end") == 2000
    # April closing balances must add up to every signed transaction
    april = "SELECT SUM(closing_balance) FROM data_bank.v_month_end WHERE month = '2020-04-01'"
    assert scalar(c, april) == scalar(c, "SELECT SUM(signed_amount) FROM data_bank.v_txn")
