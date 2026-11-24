"""取得したデータの保存先。

- local: data/ 以下に Parquet で保存（動作確認用）
- bigquery: GCS に元ファイルを保存し、BigQuery の日付パーティションを丸ごと置き換える
  （同じ日を何度流しても重複しない＝冪等）
"""

from __future__ import annotations

import os
from datetime import UTC, date, datetime
from pathlib import Path

import pandas as pd

RAW_TABLES = {
    "demand_30min": "raw_occto_demand_30min",
    "weekly": "raw_occto_weekly",
    "weather": "raw_weather_hourly",
}

FLOAT_COLUMNS = (
    "relative_humidity_2m",
    "cloud_cover",
    "temperature_2m",
    "precipitation",
    "shortwave_radiation",
)


def to_frame(rows: list[dict]) -> pd.DataFrame:
    df = pd.DataFrame(rows)
    df["ingested_at"] = datetime.now(UTC)
    for col in df.columns:
        if col.endswith(("_mw", "_pct")) or col in FLOAT_COLUMNS:
            df[col] = df[col].astype("float64")
    if "block_no" in df.columns:
        df["block_no"] = df["block_no"].astype("Int64")
    return df


class LocalSink:
    def __init__(self, base: str = "data"):
        self.base = Path(base)

    def save_raw_file(self, raw: bytes, name: str) -> str:
        p = self.base / "raw" / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(raw)
        return str(p)

    def write(self, kind: str, rows: list[dict], partition: date) -> int:
        if not rows:
            return 0
        df = to_frame(rows)
        p = self.base / RAW_TABLES[kind] / f"target_date={partition.isoformat()}.parquet"
        p.parent.mkdir(parents=True, exist_ok=True)
        df.to_parquet(p, index=False)
        return len(df)


class BigQuerySink:
    def __init__(self, project: str | None = None, dataset: str | None = None, bucket: str | None = None):
        from google.cloud import bigquery, storage

        self.project = project or os.environ["GCP_PROJECT"]
        self.dataset = dataset or os.environ.get("BQ_RAW_DATASET", "raw")
        self.bucket_name = bucket or os.environ["RAW_BUCKET"]
        self.bq = bigquery.Client(project=self.project)
        self.gcs = storage.Client(project=self.project)
        self._bigquery = bigquery
        self._schemas: dict = {}

    def save_raw_file(self, raw: bytes, name: str) -> str:
        blob = self.gcs.bucket(self.bucket_name).blob(name)
        blob.upload_from_string(raw, content_type="text/csv")
        return f"gs://{self.bucket_name}/{name}"

    def write(self, kind: str, rows: list[dict], partition: date) -> int:
        if not rows:
            return 0
        df = to_frame(rows)
        table_id = f"{self.project}.{self.dataset}.{RAW_TABLES[kind]}"
        # テーブル定義（Terraform で管理）をそのまま使う。DataFrame から推測させると必須/任意がずれるため
        if table_id not in self._schemas:
            self._schemas[table_id] = self.bq.get_table(table_id).schema
        schema = self._schemas[table_id]
        unknown = set(df.columns) - {f.name for f in schema}
        if unknown:
            raise ValueError(f"{table_id} に無い列がある: {sorted(unknown)}")
        df = df[[f.name for f in schema if f.name in df.columns]]
        job_config = self._bigquery.LoadJobConfig(
            schema=schema,
            write_disposition="WRITE_TRUNCATE",  # 指定したパーティションだけを置き換える
        )
        self.bq.load_table_from_dataframe(df, f"{table_id}${partition:%Y%m%d}", job_config=job_config).result()
        return len(df)
