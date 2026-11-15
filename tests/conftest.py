import psycopg
import pytest

from sqlcases import db


def _db_up() -> bool:
    try:
        with db.connect():
            return True
    except psycopg.OperationalError:
        return False


DB_UP = _db_up()
needs_db = pytest.mark.skipif(not DB_UP, reason="Postgres not running (uv run sqlcases up)")


@pytest.fixture(scope="session")
def seeded_conn():
    """A connection to a freshly reseeded database (every case dropped and reloaded)."""
    with db.connect() as conn:
        for name in db.case_schemas():
            conn.execute(f'DROP SCHEMA IF EXISTS "{name}" CASCADE')
        for f in db.seed_files():
            db.run_sql_file(conn, f)
        yield conn
