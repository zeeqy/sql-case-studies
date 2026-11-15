"""Database connection and SQL-file helpers."""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]

load_dotenv(ROOT / ".env")


def conninfo() -> str:
    """Build a libpq connection string from PG* env vars (defaults match docker-compose.yml)."""
    return psycopg.conninfo.make_conninfo(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "55432"),
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
    """Every schema file to load, in order: Part A cases first, then Part B."""
    files = sorted(ROOT.glob("part-a/*/schema.sql"))
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
        names.append("ewallet")
    return names
