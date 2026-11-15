"""Export Part B query results to parquet so the dashboard runs without a database.

The dashboard reads ONLY these files. Each one is the output of a real query file in
part-b/, so every chart on the dashboard is traceable to the SQL that made it.
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path

import pandas as pd
import psycopg

from sqlcases.db import ROOT

OUT = ROOT / "app" / "data"

# name -> SQL file in part-b (relative) or inline SQL for small helper tables
SOURCES: dict[str, str] = {
    "mau": "queries/01_monthly_active_users.sql",
    "retention": "queries/03_retention_cohorts.sql",
    "churn": "queries/04_churn_by_segment.sql",
    "rfm": "queries/05_rfm_segments.sql",
    "category_mix": "queries/06_category_mix_shift.sql",
    "category_yoy": "queries/07_category_yoy_growth.sql",
    "promo_uplift": "queries/09_promo_uplift.sql",
    "promo_roi": "queries/10_promo_roi.sql",
    "mules": "queries/11_fraud_mule_bursts.sql",
    "round_amounts": "queries/12_round_amount_profile.sql",
    "funnel": "queries/13_activation_funnel.sql",
    "topups": "queries/14_topup_behaviour.sql",
    "peak_hours": "queries/15_peak_hours.sql",
    "fraud_eval": "eval/fraud_eval.sql",
}

INLINE: dict[str, str] = {
    # planted truth, shown on the dashboard next to the estimates (synthetic data only)
    "promo_truth": "SELECT promo_id, true_uplift FROM ewallet_truth.promo_uplift",
    "kpis": """
        SELECT (SELECT COUNT(*) FROM ewallet.users) AS users,
               (SELECT SUM(amount) FROM ewallet.v_merchant_txn
                 WHERE txn_date >= DATE '2025-01-01') AS gmv_2025,
               (SELECT SUM(amount) FROM ewallet.v_merchant_txn
                 WHERE txn_date < DATE '2025-01-01') AS gmv_2024,
               (SELECT COUNT(*) FROM ewallet.transactions) AS transactions""",
}


def _last_frame(conn: psycopg.Connection, sql: str) -> pd.DataFrame:
    cur = conn.execute(sql)
    while cur.nextset():  # step to the final statement's result (files start with SET)
        pass
    cols = [d.name for d in cur.description]
    df = pd.DataFrame(cur.fetchall(), columns=cols)
    for c in df.columns:  # NUMERIC arrives as Decimal; parquet/plotly want floats
        if df[c].map(lambda v: isinstance(v, Decimal)).any():
            df[c] = df[c].astype(float)
    return df


def snapshot(conn: psycopg.Connection, out: Path = OUT) -> dict[str, int]:
    out.mkdir(parents=True, exist_ok=True)
    rows = {}
    for name, rel in SOURCES.items():
        df = _last_frame(conn, (ROOT / "part-b" / rel).read_text(encoding="utf-8"))
        df.to_parquet(out / f"{name}.parquet", index=False)
        rows[name] = len(df)
    for name, sql in INLINE.items():
        df = _last_frame(conn, sql)
        df.to_parquet(out / f"{name}.parquet", index=False)
        rows[name] = len(df)
    return rows
