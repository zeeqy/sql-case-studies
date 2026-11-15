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


def _psql_file(path) -> str:
    """Run a .sql file with psql inside the container and return its formatted output."""
    with open(path, "rb") as f:
        res = subprocess.run(
            [
                "docker",
                "exec",
                "-i",
                "sqlcases-db",
                "psql",
                "-U",
                "sqlcases",
                "-d",
                "sqlcases",
                "-v",
                "ON_ERROR_STOP=1",
                "-q",
                "-P",
                "pager=off",
            ],
            stdin=f,
            capture_output=True,
            check=False,
        )
    if res.returncode:
        raise SystemExit(f"{path.name} failed:\n{res.stderr.decode()}")
    return res.stdout.decode().replace("\r\n", "\n")


def cmd_results(_: argparse.Namespace) -> None:
    """Run every Part B query and save its output, so results are readable without a database."""
    out_dir = db.ROOT / "part-b" / "results"
    out_dir.mkdir(exist_ok=True)
    for q in sorted((db.ROOT / "part-b" / "queries").glob("*.sql")):
        text = _psql_file(q)
        (out_dir / f"{q.stem}.txt").write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote part-b/results/{q.stem}.txt")


INDEXES = ["ix_txn_wallet_ts", "ix_txn_counterparty_ts", "ix_txn_merchant", "ix_txn_ts_brin"]


def _explain(conn, sql: str, runs: int = 5) -> tuple[str, float]:
    """EXPLAIN ANALYZE a query several times; keep the fastest run (warm cache, less noise)."""
    best_plan, best_ms = "", float("inf")
    for _ in range(runs):
        rows = conn.execute(f"EXPLAIN (ANALYZE, BUFFERS) {sql}").fetchall()
        plan = "\n".join(r[0] for r in rows)
        ms = float(plan.rsplit("Execution Time: ", 1)[1].split(" ")[0])
        if ms < best_ms:
            best_plan, best_ms = plan, ms
    return best_plan, best_ms


def cmd_explain(_: argparse.Namespace) -> None:
    """Time the demo queries without and with indexes; write plans and a summary table."""
    text = (db.ROOT / "part-b" / "explain" / "demo_queries.sql").read_text(encoding="utf-8")
    blocks = [b for b in text.split("-- name: ")[1:]]
    queries = {b.split("\n", 1)[0].strip(): b.split("\n", 1)[1] for b in blocks}
    out = db.ROOT / "part-b" / "explain"
    results: dict[str, dict[str, float]] = {}
    with db.connect() as conn:
        for phase in ("before", "after"):
            if phase == "before":
                for ix in INDEXES:
                    conn.execute(f"DROP INDEX IF EXISTS ewallet.{ix}")
            else:
                db.run_sql_file(conn, db.ROOT / "part-b" / "indexes.sql")
            conn.execute("ANALYZE ewallet.transactions")
            report = []
            for name, sql in queries.items():
                plan, ms = _explain(conn, sql)
                results.setdefault(name, {})[phase] = ms
                report.append(f"===== {name} ({phase} indexes): {ms:.1f} ms\n{plan}\n")
            (out / f"{phase}.txt").write_text("\n".join(report), encoding="utf-8", newline="\n")
    lines = ["| Query | Before (ms) | After (ms) | Speed-up |", "|---|---:|---:|---:|"]
    for name, r in results.items():
        lines.append(
            f"| {name} | {r['before']:.1f} | {r['after']:.1f} | {r['before'] / r['after']:.1f}x |"
        )
    (out / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("\n".join(lines))


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
    sub.add_parser("explain", help="EXPLAIN ANALYZE demo, before/after indexes").set_defaults(
        func=cmd_explain
    )
    sub.add_parser("results", help="run Part B queries, save outputs").set_defaults(
        func=cmd_results
    )

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
