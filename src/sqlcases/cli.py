"""One-command workflow: `uv run sqlcases up` starts Postgres and seeds every case."""

from __future__ import annotations

import argparse
import subprocess
import sys

from sqlcases import db


def _compose(*args: str) -> None:
    subprocess.run(["docker", "compose", *args], cwd=db.ROOT, check=True)


def cmd_seed(_: argparse.Namespace) -> None:
    if not db.seed_files():
        print("Nothing to seed yet (no schema.sql files).")
        return
    with db.connect() as conn:
        db.seed_all(conn)
    print("Seed complete.")


def cmd_up(args: argparse.Namespace) -> None:
    profile = ["--profile", "gui"] if args.gui else []
    _compose(*profile, "up", "-d", "--wait")
    cmd_seed(args)
    if args.gui:
        print("pgAdmin: http://localhost:55050 (host 'db', port 5432)")


def cmd_down(args: argparse.Namespace) -> None:
    _compose("--profile", "gui", "down", *(["-v"] if args.volumes else []))


def cmd_reset(args: argparse.Namespace) -> None:
    """Drop every case schema and reseed, for a clean slate without restarting Docker."""
    with db.connect() as conn:
        for name in db.case_schemas():
            conn.execute(f'DROP SCHEMA IF EXISTS "{name}" CASCADE')
    cmd_seed(args)


def cmd_psql(_: argparse.Namespace) -> None:
    # psql inside the container, so nothing needs installing on Windows.
    subprocess.run(
        ["docker", "exec", "-it", "sqlcases-db", "psql", "-U", "sqlcases", "-d", "sqlcases"]
    )


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="sqlcases", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    up = sub.add_parser("up", help="start Postgres and seed all cases")
    up.add_argument("--gui", action="store_true", help="also start pgAdmin")
    up.set_defaults(func=cmd_up)

    sub.add_parser("seed", help="load every schema.sql").set_defaults(func=cmd_seed)
    sub.add_parser("reset", help="drop case schemas and reseed").set_defaults(func=cmd_reset)
    sub.add_parser("psql", help="open psql in the container").set_defaults(func=cmd_psql)

    down = sub.add_parser("down", help="stop containers")
    down.add_argument("-v", "--volumes", action="store_true", help="also delete the data volume")
    down.set_defaults(func=cmd_down)

    args = p.parse_args(argv)
    try:
        args.func(args)
    except subprocess.CalledProcessError as e:
        sys.exit(f"docker compose failed ({e.returncode}). Is Docker Desktop running?")


if __name__ == "__main__":
    main()
