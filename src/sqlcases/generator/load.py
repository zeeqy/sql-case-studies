"""Bulk-load a generated World into the ewallet schema with COPY (much faster than INSERTs)."""

from __future__ import annotations

import psycopg

from sqlcases.generator.simulate import World

TABLES = [  # parents before children, so foreign keys are satisfied
    ("ewallet.users", "users"),
    ("ewallet.wallets", "wallets"),
    ("ewallet.merchants", "merchants"),
    ("ewallet.promotions", "promotions"),
    ("ewallet.transactions", "transactions"),
    ("ewallet_truth.mule_bursts", "mule_bursts"),
    ("ewallet_truth.promo_uplift", "promo_uplift"),
]


def load(conn: psycopg.Connection, world: World) -> dict[str, int]:
    counts = {}
    with conn.transaction():
        for table, attr in TABLES:
            rows = getattr(world, attr)
            with conn.cursor().copy(f"COPY {table} FROM STDIN") as copy:
                for row in rows:
                    copy.write_row(row)
            counts[table] = len(rows)
        conn.execute("ANALYZE ewallet.transactions")  # fresh planner stats for EXPLAIN
    return counts
