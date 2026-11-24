locals {
  datasets = {
    raw     = "取り込んだままのデータ（Python が書き込む）"
    staging = "dbt: 型変換・整形をした中間層"
    marts   = "dbt: ダッシュボード用に集計した層"
  }

  file_meta_fields = [
    { name = "raw_file_uri", type = "STRING", mode = "NULLABLE", description = "保存した元 CSV の場所" },
    { name = "file_sha256", type = "STRING", mode = "NULLABLE", description = "元 CSV のハッシュ値" },
    { name = "ingested_at", type = "TIMESTAMP", mode = "REQUIRED" },
  ]

  occto_metric_fields = [
    { name = "block_demand_mw", type = "FLOAT64", mode = "NULLABLE", description = "広域ブロック需要" },
    { name = "block_supply_mw", type = "FLOAT64", mode = "NULLABLE", description = "広域ブロック供給力" },
    { name = "block_reserve_mw", type = "FLOAT64", mode = "NULLABLE", description = "広域ブロック予備力" },
    { name = "block_reserve_rate_pct", type = "FLOAT64", mode = "NULLABLE", description = "広域予備率" },
    { name = "block_usage_rate_pct", type = "FLOAT64", mode = "NULLABLE", description = "広域使用率" },
    { name = "area_demand_mw", type = "FLOAT64", mode = "NULLABLE", description = "エリア需要" },
    { name = "area_supply_mw", type = "FLOAT64", mode = "NULLABLE", description = "エリア供給力" },
    { name = "area_reserve_mw", type = "FLOAT64", mode = "NULLABLE", description = "エリア予備力" },
  ]

  raw_tables = {
    raw_occto_demand_30min = {
      description = "OCCTO 広域予備率Web公表システム 30分値（翌々日予測・当日最終値）。全10エリア"
      clustering  = ["kind", "area"]
      fields = concat([
        { name = "target_date", type = "DATE", mode = "REQUIRED" },
        { name = "kind", type = "STRING", mode = "REQUIRED", description = "two_day_ahead / same_day" },
        { name = "published_at", type = "TIMESTAMP", mode = "REQUIRED", description = "CSV の公表時刻（いつ時点の値か）" },
        { name = "area", type = "STRING", mode = "REQUIRED" },
        { name = "block_no", type = "INT64", mode = "NULLABLE" },
        { name = "slot_start", type = "TIMESTAMP", mode = "REQUIRED", description = "30分コマの開始時刻" },
      ], local.occto_metric_fields, local.file_meta_fields)
    }
    raw_occto_weekly = {
      description = "OCCTO 広域予備率Web公表システム 週間（最大需要・最小予備率の時点）。全10エリア"
      clustering  = ["area"]
      fields = concat([
        { name = "target_date", type = "DATE", mode = "REQUIRED" },
        { name = "kind", type = "STRING", mode = "REQUIRED" },
        { name = "published_at", type = "TIMESTAMP", mode = "REQUIRED" },
        { name = "area", type = "STRING", mode = "REQUIRED" },
        { name = "block_no", type = "INT64", mode = "NULLABLE" },
        { name = "category", type = "STRING", mode = "REQUIRED", description = "最大需要 / 最小予備率" },
        { name = "slot_start", type = "TIMESTAMP", mode = "REQUIRED" },
      ], local.occto_metric_fields, local.file_meta_fields)
    }
    raw_weather_hourly = {
      description = "Open-Meteo 九州8都市の1時間値"
      clustering  = ["city_id"]
      fields = [
        { name = "target_date", type = "DATE", mode = "REQUIRED" },
        { name = "hour_start", type = "TIMESTAMP", mode = "REQUIRED" },
        { name = "city_id", type = "STRING", mode = "REQUIRED" },
        { name = "prefecture", type = "STRING", mode = "REQUIRED" },
        { name = "temperature_2m", type = "FLOAT64", mode = "NULLABLE" },
        { name = "relative_humidity_2m", type = "FLOAT64", mode = "NULLABLE" },
        { name = "precipitation", type = "FLOAT64", mode = "NULLABLE" },
        { name = "cloud_cover", type = "FLOAT64", mode = "NULLABLE" },
        { name = "shortwave_radiation", type = "FLOAT64", mode = "NULLABLE" },
        { name = "source_url", type = "STRING", mode = "NULLABLE" },
        { name = "ingested_at", type = "TIMESTAMP", mode = "REQUIRED" },
      ]
    }
  }
}

resource "google_bigquery_dataset" "ds" {
  for_each    = local.datasets
  dataset_id  = each.key
  location    = var.region
  description = each.value
  depends_on  = [google_project_service.apis]
}

# CI（プルリクエスト）用。テーブルは1日で自動削除
resource "google_bigquery_dataset" "ci" {
  dataset_id                  = "ci"
  location                    = var.region
  description                 = "GitHub Actions の dbt build 用（1日で自動削除）"
  default_table_expiration_ms = 86400000
  depends_on                  = [google_project_service.apis]
}

resource "google_bigquery_table" "raw" {
  for_each            = local.raw_tables
  dataset_id          = google_bigquery_dataset.ds["raw"].dataset_id
  table_id            = each.key
  description         = each.value.description
  deletion_protection = true
  clustering          = each.value.clustering

  time_partitioning {
    type  = "DAY"
    field = "target_date"
  }

  schema = jsonencode(each.value.fields)
}
