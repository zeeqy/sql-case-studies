import psycopg
import pytest

from sqlcases import db


def test_case_schema_names_follow_folder_names(tmp_path, monkeypatch):
    (tmp_path / "part-a" / "01-dannys-diner").mkdir(parents=True)
    (tmp_path / "part-a" / "01-dannys-diner" / "schema.sql").write_text("")
    (tmp_path / "part-a" / "04-data-bank").mkdir(parents=True)
    (tmp_path / "part-a" / "04-data-bank" / "schema.sql").write_text("")
    (tmp_path / "part-b").mkdir()
    (tmp_path / "part-b" / "schema.sql").write_text("")
    monkeypatch.setattr(db, "ROOT", tmp_path)

    assert db.case_schemas() == ["dannys_diner", "data_bank", "ewallet"]
    assert [f.parent.name for f in db.seed_files()] == ["01-dannys-diner", "04-data-bank", "part-b"]


def _db_up() -> bool:
    try:
        with db.connect():
            return True
    except psycopg.OperationalError:
        return False


@pytest.mark.db
@pytest.mark.skipif(not _db_up(), reason="Postgres container not running (uv run sqlcases up)")
def test_postgres_is_16_and_runs_multi_statement_files(tmp_path):
    sql = tmp_path / "t.sql"
    sql.write_text("CREATE TEMP TABLE t (x int); INSERT INTO t VALUES (1), (2);")
    with db.connect() as conn:
        assert conn.info.server_version >= 160000
        db.run_sql_file(conn, sql)
        assert conn.execute("SELECT sum(x) FROM t").fetchone()[0] == 3
