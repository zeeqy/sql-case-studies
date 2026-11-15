from conftest import needs_db

from sqlcases import db


def test_seed_order_and_schema_names(tmp_path, monkeypatch):
    for case in ("01-dannys-diner", "02-pizza-runner", "04-data-bank"):
        (tmp_path / "part-a" / case).mkdir(parents=True)
        (tmp_path / "part-a" / case / "schema.sql").write_text("")
    (tmp_path / "part-a" / "02-pizza-runner" / "cleaning.sql").write_text("")
    (tmp_path / "part-b").mkdir()
    (tmp_path / "part-b" / "schema.sql").write_text("")
    monkeypatch.setattr(db, "ROOT", tmp_path)

    assert db.case_schemas() == ["dannys_diner", "pizza_runner", "data_bank", "ewallet"]
    # cleaning.sql must run straight after its own schema.sql
    assert [f.relative_to(tmp_path).as_posix() for f in db.seed_files()] == [
        "part-a/01-dannys-diner/schema.sql",
        "part-a/02-pizza-runner/schema.sql",
        "part-a/02-pizza-runner/cleaning.sql",
        "part-a/04-data-bank/schema.sql",
        "part-b/schema.sql",
    ]


@needs_db
def test_postgres_16_runs_multi_statement_files(tmp_path):
    sql = tmp_path / "t.sql"
    sql.write_text("CREATE TEMP TABLE t (x int); INSERT INTO t VALUES (1), (2);")
    with db.connect() as conn:
        assert conn.info.server_version >= 160000
        db.run_sql_file(conn, sql)
        assert conn.execute("SELECT sum(x) FROM t").fetchone()[0] == 3
