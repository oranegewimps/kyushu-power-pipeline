"""整合性チェック（突き合わせ）。

取り込みの各段階で、データが欠けたり変わったりしていないかを確かめる。

  1. 元データ ↔ 保存した元CSV : OCCTO から取り直したファイルと GCS のファイルのハッシュ値を比べる（抜き取り）
  2. 元CSV ↔ BigQuery raw     : GCS の CSV を「取り込みとは別の簡単な読み方」で集計し、BigQuery の集計と比べる
                                （件数・需要と供給力の合計・ファイルのハッシュ値）
  3. raw ↔ dbt の集計結果     : staging と fct の件数・合計が一致するか

パーサーの不具合を見逃さないよう、2 では ingestion.occto のパーサーを使わずに CSV を読む。

例:
  python -m ingestion.reconcile --start 2025-04-01 --end 2026-11-20 --source-samples 5
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import logging
import os
import random
import sys
import time
from collections import defaultdict
from datetime import date, datetime, timedelta

from ingestion import occto

log = logging.getLogger("reconcile")
TOLERANCE = 1e-6  # 浮動小数の誤差の許容（相対）


def _close(a: float | None, b: float | None) -> bool:
    if a is None or b is None:
        return a is b
    return abs(a - b) <= TOLERANCE * max(1.0, abs(a), abs(b))


def summarize_csv(raw: bytes) -> dict[str, dict]:
    """取り込みのパーサーとは独立した、最小限の読み方でエリアごとに集計する。"""
    lines = raw.decode("utf-8-sig").splitlines()[1:]  # 1行目は公表時刻
    out: dict[str, dict] = defaultdict(lambda: {"rows": 0, "demand": 0.0, "supply": 0.0})
    for rec in csv.DictReader(io.StringIO("\n".join(lines))):
        a = out[rec["エリア名"]]
        a["rows"] += 1
        for key, col in (("demand", "エリア需要(MW)"), ("supply", "エリア供給力(MW)")):
            v = (rec.get(col) or "").strip()
            if v not in ("", "-", "***"):
                a[key] += float(v)
    return dict(out)


def daterange(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


class Reconciler:
    def __init__(self, project: str, bucket: str, dataset: str = "raw", marts_dataset: str = "marts"):
        from google.cloud import bigquery, storage

        self.project, self.dataset, self.marts = project, dataset, marts_dataset
        self.bq = bigquery.Client(project=project)
        self.bucket = storage.Client(project=project).bucket(bucket)
        self._bigquery = bigquery

    def _query(self, sql: str, **params) -> list[dict]:
        qp = [
            self._bigquery.ScalarQueryParameter(k, "DATE" if isinstance(v, date) else "STRING", v)
            for k, v in params.items()
        ]
        job = self.bq.query(sql, job_config=self._bigquery.QueryJobConfig(query_parameters=qp))
        return [dict(r) for r in job.result()]

    # --- 2. 元CSV ↔ BigQuery raw ---------------------------------------------------------
    def bigquery_summary(self, start: date, end: date) -> dict[tuple, dict]:
        sql = f"""
            select target_date, kind, area, count(*) rows_, sum(area_demand_mw) demand, sum(area_supply_mw) supply,
                   any_value(file_sha256) sha, count(distinct file_sha256) n_sha
            from (
              select target_date, kind, area, area_demand_mw, area_supply_mw, file_sha256
              from `{self.project}.{self.dataset}.raw_occto_demand_30min`
              where target_date between @start and @end
              union all
              select target_date, kind, area, area_demand_mw, area_supply_mw, file_sha256
              from `{self.project}.{self.dataset}.raw_occto_weekly`
              where target_date between @start and @end
            )
            group by 1, 2, 3
        """
        return {(r["target_date"], r["kind"], r["area"]): r for r in self._query(sql, start=start, end=end)}

    def check_files_vs_bigquery(self, start: date, end: date) -> dict:
        bq = self.bigquery_summary(start, end)
        problems: list[str] = []
        files = 0
        seen: set[tuple] = set()
        for d in daterange(start, end):
            for kind in occto.KINDS:
                name = f"occto/{kind}/{d:%Y/%m}/{d:%Y%m%d}.csv"
                blob = self.bucket.blob(name)
                if not blob.exists():
                    problems.append(f"元CSVが無い: {name}")
                    continue
                raw = blob.download_as_bytes()
                files += 1
                sha = hashlib.sha256(raw).hexdigest()
                for area, s in summarize_csv(raw).items():
                    key = (d, kind, area)
                    seen.add(key)
                    b = bq.get(key)
                    if b is None:
                        problems.append(f"BigQuery に無い: {key}")
                        continue
                    if b["rows_"] != s["rows"]:
                        problems.append(f"件数が違う {key}: CSV={s['rows']} BQ={b['rows_']}")
                    if not _close(b["demand"], s["demand"]):
                        problems.append(f"需要の合計が違う {key}: CSV={s['demand']} BQ={b['demand']}")
                    if not _close(b["supply"], s["supply"]):
                        problems.append(f"供給力の合計が違う {key}: CSV={s['supply']} BQ={b['supply']}")
                    if b["sha"] != sha or b["n_sha"] != 1:
                        problems.append(f"ハッシュ値が違う {key}（別のファイルから入った行がある）")
        for key in set(bq) - seen:
            problems.append(f"元CSVに無い行が BigQuery にある: {key}")
        return {"files_checked": files, "groups_checked": len(seen), "problems": problems}

    # --- 1. 元データ ↔ 保存した元CSV（抜き取り） --------------------------------------------
    def check_source_samples(self, start: date, end: date, n: int, seed: int | None = None) -> dict:
        days = list(daterange(start, end))
        rng = random.Random(seed)
        sample = sorted(rng.sample(days, min(n, len(days))))
        session = occto.new_session()
        problems, revised = [], []
        for d in sample:
            for kind in occto.KINDS:
                live = occto.fetch_csv(session, kind, d)
                time.sleep(2)  # 公開サーバーへの配慮
                stored = self.bucket.blob(f"occto/{kind}/{d:%Y/%m}/{d:%Y%m%d}.csv").download_as_bytes()
                if live == stored:
                    continue
                # 公表値は過去にさかのぼり修正されることがある → 内容の集計で差を確認する
                a, b = summarize_csv(live), summarize_csv(stored)
                if a.keys() != b.keys() or any(a[k]["rows"] != b[k]["rows"] for k in a):
                    problems.append(f"{d} {kind}: 取り直したファイルと構造（エリア・件数）が違う")
                else:
                    diffs = {
                        k: round(a[k]["demand"] - b[k]["demand"], 3)
                        for k in a
                        if not _close(a[k]["demand"], b[k]["demand"])
                    }
                    revised.append(
                        f"{d} {kind}: 公表値が修正されている可能性 {diffs or '（数値は同じ・更新時刻のみ違う）'}"
                    )
        return {"sampled_days": [d.isoformat() for d in sample], "problems": problems, "revised": revised}

    # --- 3. raw ↔ dbt の集計結果 -----------------------------------------------------------
    def check_marts(self, start: date, end: date) -> dict:
        sql = f"""
            with s as (
              select target_date, area,
                     countif(kind = 'same_day') final_rows,
                     sum(if(kind = 'same_day', area_demand_mw, 0)) final_sum,
                     countif(kind = 'two_day_ahead') fcst_rows,
                     sum(if(kind = 'two_day_ahead', area_demand_mw, 0)) fcst_sum
              from `{self.project}.staging.stg_occto__demand_30min`
              where target_date between @start and @end
              group by 1, 2
            ),
            f as (
              select target_date, area,
                     countif(final_mw is not null) final_rows, sum(ifnull(final_mw, 0)) final_sum,
                     countif(forecast_mw is not null) fcst_rows, sum(ifnull(forecast_mw, 0)) fcst_sum
              from `{self.project}.{self.marts}.fct_area_demand_30min`
              where target_date between @start and @end
              group by 1, 2
            )
            select coalesce(s.target_date, f.target_date) target_date, coalesce(s.area, f.area) area,
                   s.final_rows s_fr, f.final_rows f_fr, s.final_sum s_fs, f.final_sum f_fs,
                   s.fcst_rows s_pr, f.fcst_rows f_pr, s.fcst_sum s_ps, f.fcst_sum f_ps
            from s full outer join f using (target_date, area)
        """
        problems = []
        rows = self._query(sql, start=start, end=end)
        for r in rows:
            key = (r["target_date"], r["area"])
            if r["s_fr"] != r["f_fr"] or r["s_pr"] != r["f_pr"]:
                problems.append(f"件数が違う {key}: staging={r['s_fr']}/{r['s_pr']} fct={r['f_fr']}/{r['f_pr']}")
            elif not (_close(r["s_fs"], r["f_fs"]) and _close(r["s_ps"], r["f_ps"])):
                problems.append(f"合計が違う {key}")
        return {"groups_checked": len(rows), "problems": problems}


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser()
    today = datetime.now(occto.JST).date()
    p.add_argument("--start", type=date.fromisoformat, default=today - timedelta(days=3))
    p.add_argument("--end", type=date.fromisoformat, default=today - timedelta(days=1))
    p.add_argument("--source-samples", type=int, default=0, help="OCCTO から取り直して比べる日数（抜き取り）")
    p.add_argument("--skip-marts", action="store_true", help="dbt の集計結果との突き合わせを省く")
    p.add_argument("--seed", type=int, default=None)
    args = p.parse_args(argv)

    r = Reconciler(project=os.environ["GCP_PROJECT"], bucket=os.environ["RAW_BUCKET"])
    report: dict = {"range": [args.start.isoformat(), args.end.isoformat()]}
    report["files_vs_bigquery"] = r.check_files_vs_bigquery(args.start, args.end)
    if args.source_samples:
        report["source_vs_files"] = r.check_source_samples(args.start, args.end, args.source_samples, args.seed)
    if not args.skip_marts:
        report["raw_vs_marts"] = r.check_marts(args.start, args.end)

    n_problems = sum(len(v.get("problems", [])) for v in report.values() if isinstance(v, dict))
    report["result"] = "OK" if n_problems == 0 else f"NG（{n_problems} 件）"
    print(json.dumps(report, ensure_ascii=False, default=str, indent=2))
    return 0 if n_problems == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
