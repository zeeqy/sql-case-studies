"""The dashboard must render from the committed snapshot alone, with no database."""

import pandas as pd
from conftest import needs_db
from streamlit.testing.v1 import AppTest

from sqlcases import db
from sqlcases.snapshot import INLINE, SOURCES, snapshot

APP = db.ROOT / "app" / "streamlit_app.py"
DATA = db.ROOT / "app" / "data"


def test_snapshot_files_are_committed():
    for name in list(SOURCES) + list(INLINE):
        df = pd.read_parquet(DATA / f"{name}.parquet")
        assert len(df) > 0, name


def test_app_renders_every_tab_without_errors():
    at = AppTest.from_file(str(APP), default_timeout=60).run()
    assert not at.exception, at.exception
    assert len(at.tabs) == 6
    assert at.metric[0].value == f"{int(pd.read_parquet(DATA / 'mau.parquet').mau.iloc[-1]):,}"


@needs_db
def test_snapshot_matches_live_queries(seeded_conn, tmp_path):
    rows = snapshot(seeded_conn, out=tmp_path)
    assert rows["mau"] == 24
    assert rows["promo_uplift"] == 6
    # the committed snapshot is the same data as a fresh run (seeded generator)
    fresh = pd.read_parquet(tmp_path / "rfm.parquet")
    committed = pd.read_parquet(DATA / "rfm.parquet")
    pd.testing.assert_frame_equal(fresh, committed)
