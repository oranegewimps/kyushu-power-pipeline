"""取り込みの入口。

例:
  python -m ingestion.main                                    # 3日前〜昨日を取り込み（速報値の修正を拾うため）
  python -m ingestion.main --start 2025-04-01 --end 2026-11-23  # 過去分の一括取り込み
  python -m ingestion.main --sink local                       # BigQuery ではなく data/ に保存
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from datetime import date, datetime, timedelta

import requests

from ingestion import occto, weather
from ingestion.load import BigQuerySink, LocalSink

log = logging.getLogger("ingestion")
REQUEST_INTERVAL_SEC = 2.0  # 公開サーバーに負担をかけないため、リクエストの間を2秒あける


def daterange(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def ingest_day(session: requests.Session, sink, d: date) -> dict:
    """1日分の3種類の CSV を取得し、30分値（翌々日・当日）と週間の2テーブルに書き込む。"""
    rows_30min: list[dict] = []
    rows_weekly: list[dict] = []
    warnings: list[str] = []
    for kind in occto.KINDS:
        raw = occto.fetch_csv(session, kind, d)
        uri = sink.save_raw_file(raw, f"occto/{kind}/{d:%Y/%m}/{d:%Y%m%d}.csv")
        parsed = occto.parse_csv(raw, kind, d)
        meta = {"raw_file_uri": uri, "file_sha256": occto.sha256(raw)}
        target = rows_weekly if kind == "weekly" else rows_30min
        target.extend({**r, **meta} for r in parsed.rows)
        warnings.extend(parsed.warnings)
        time.sleep(REQUEST_INTERVAL_SEC)
    # 1日分をまとめてパーティションごと置き換える（翌々日と当日を同じパーティションに入れるため）
    n30 = sink.write("demand_30min", rows_30min, d)
    nwk = sink.write("weekly", rows_weekly, d)
    return {"demand_30min": n30, "weekly": nwk, "warnings": warnings}


def run(start: date, end: date, sink, with_weather: bool = True) -> dict:
    session = occto.new_session()
    summary: dict = {"days_ok": 0, "days_failed": [], "warnings": {}, "rows": {"demand_30min": 0, "weekly": 0}}

    for d in daterange(start, end):
        try:
            r = ingest_day(session, sink, d)
            summary["rows"]["demand_30min"] += r["demand_30min"]
            summary["rows"]["weekly"] += r["weekly"]
            if r["warnings"]:
                summary["warnings"][d.isoformat()] = r["warnings"]
            summary["days_ok"] += 1
        except (requests.HTTPError, occto.SchemaChangedError, occto.DataNotAvailableError) as e:
            log.error("%s: %s", d, e)
            summary["days_failed"].append({"date": d.isoformat(), "error": str(e)})
            time.sleep(REQUEST_INTERVAL_SEC)

    if with_weather:
        summary["rows"]["weather"] = 0
        chunk_start = start
        while chunk_start <= end:
            chunk_end = min(chunk_start + timedelta(days=30), end)
            rows = weather.fetch_weather(chunk_start, chunk_end)
            for d in daterange(chunk_start, chunk_end):
                day_rows = [{**r, "source_url": "open-meteo"} for r in rows if r["target_date"] == d]
                summary["rows"]["weather"] += sink.write("weather", day_rows, d)
            chunk_start = chunk_end + timedelta(days=1)
            time.sleep(REQUEST_INTERVAL_SEC)

    return summary


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser()
    today = datetime.now(occto.JST).date()
    p.add_argument("--start", type=date.fromisoformat, default=today - timedelta(days=3))
    p.add_argument("--end", type=date.fromisoformat, default=today - timedelta(days=1))
    p.add_argument("--sink", choices=["local", "bigquery"], default="bigquery")
    p.add_argument("--no-weather", action="store_true")
    args = p.parse_args(argv)

    sink = LocalSink() if args.sink == "local" else BigQuerySink()
    summary = run(args.start, args.end, sink, with_weather=not args.no_weather)
    print(json.dumps(summary, ensure_ascii=False, default=str, indent=2))
    # 1日でも失敗したら終了コード1 → ワークフローが失敗し、メール通知される
    return 1 if summary["days_failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
