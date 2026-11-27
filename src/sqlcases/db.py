"""Database connection and SQL-file helpers."""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]

load_dotenv(ROOT / ".env")


def conninfo() -> str:
    """Build a libpq connection string from DB_PORT + PG* env vars (defaults match compose)."""
    return psycopg.conninfo.make_conninfo(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("DB_PORT", "54432"),
        user=os.getenv("PGUSER", "sqlcases"),
        password=os.getenv("PGPASSWORD", "sqlcases"),
        dbname=os.getenv("PGDATABASE", "sqlcases"),
    )


def connect() -> psycopg.Connection:
    return psycopg.connect(conninfo(), autocommit=True)


def run_sql_file(conn: psycopg.Connection, path: Path) -> None:
    """Run a whole .sql file in one round trip.

    Passing no parameters makes psycopg use the simple query protocol,
    which accepts many statements separated by semicolons.
    """
    conn.execute(path.read_text(encoding="utf-8"))


def seed_files() -> list[Path]:
    """Every file to load, in order: Part A cases first, then Part B.

    A case folder may also have cleaning.sql, which runs right after its schema.sql.
    """
    files = []
    for schema in sorted(ROOT.glob("part-a/*/schema.sql")):
        files.append(schema)
        cleaning = schema.parent / "cleaning.sql"
        if cleaning.exists():
            files.append(cleaning)
    part_b = ROOT / "part-b" / "schema.sql"
    if part_b.exists():
        files.append(part_b)
    return files


def case_schemas() -> list[str]:
    """Postgres schema names owned by this project, one per case folder.

    Folder `part-a/01-dannys-diner` -> schema `dannys_diner`; Part B -> `ewallet`.
    """
    names = []
    for f in sorted(ROOT.glob("part-a/*/schema.sql")):
        names.append(f.parent.name.split("-", 1)[1].replace("-", "_"))
    if (ROOT / "part-b" / "schema.sql").exists():
        names += ["ewallet", "ewallet_truth"]
    return names


def seed_all(conn: psycopg.Connection, n_users: int | None = None, log=print) -> None:
    """Load every case. Part B data comes from the seeded generator, not a SQL file."""
    for f in seed_files():
        log(f"seeding {f.relative_to(ROOT).as_posix()}")
        run_sql_file(conn, f)
    if (ROOT / "part-b" / "schema.sql").exists():
        from sqlcases.generator import config
        from sqlcases.generator.load import load
        from sqlcases.generator.simulate import generate

        n = n_users or config.N_USERS
        log(f"generating e-wallet data ({n} users, seed {config.SEED})...")
        counts = load(conn, generate(n_users=n))
        log("  " + ", ".join(f"{t.split('.')[1]}={c:,}" for t, c in counts.items()))
        for extra in ("indexes.sql", "views.sql"):
            path = ROOT / "part-b" / extra
            if path.exists():
                log(f"applying part-b/{extra}")
                run_sql_file(conn, path)
