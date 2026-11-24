"""整合性チェックの「独立した読み方」が、取り込みのパーサーと同じ集計になることを確かめる。"""

from datetime import date

from ingestion.occto import parse_csv
from ingestion.reconcile import _close, summarize_csv
from tests.test_occto import make_same_day, make_two_day, make_weekly


def _from_parser(raw: bytes, kind: str) -> dict:
    out: dict = {}
    for r in parse_csv(raw, kind, date(2026, 11, 22)).rows:
        a = out.setdefault(r["area"], {"rows": 0, "demand": 0.0, "supply": 0.0})
        a["rows"] += 1
        a["demand"] += r["area_demand_mw"] or 0
        a["supply"] += r["area_supply_mw"] or 0
    return out


def test_independent_summary_matches_parser():
    for raw, kind in ((make_same_day(), "same_day"), (make_two_day(), "two_day_ahead"), (make_weekly(), "weekly")):
        assert summarize_csv(raw) == _from_parser(raw, kind)


def test_close_handles_float_noise_and_none():
    assert _close(0.1 + 0.2, 0.3)
    assert not _close(100.0, 101.0)
    assert _close(None, None)
    assert not _close(None, 1.0)
