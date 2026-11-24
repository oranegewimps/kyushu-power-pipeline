# サービスアカウントは役割ごとに分け、必要な権限だけを付ける（最小権限）

resource "google_service_account" "ingestion" {
  account_id   = "sa-ingestion"
  display_name = "取り込みジョブ"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "dbt" {
  account_id   = "sa-dbt"
  display_name = "dbt ジョブ / CI"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "orchestrator" {
  account_id   = "sa-orchestrator"
  display_name = "Scheduler と Workflows"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "deployer" {
  account_id   = "sa-github-deployer"
  display_name = "GitHub Actions のデプロイ"
  depends_on   = [google_project_service.apis]
}

# --- 取り込み: raw への書き込みとバケットへの保存だけ ---
resource "google_bigquery_dataset_iam_member" "ingestion_raw" {
  dataset_id = google_bigquery_dataset.ds["raw"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.ingestion.member
}

resource "google_storage_bucket_iam_member" "ingestion_raw_bucket" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectUser"
  member = google_service_account.ingestion.member
}

# 整合性チェック（取り込み用SAで実行）: staging / marts は読むだけ
resource "google_bigquery_dataset_iam_member" "ingestion_read_dbt_outputs" {
  for_each   = toset(["staging", "marts"])
  dataset_id = google_bigquery_dataset.ds[each.value].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.ingestion.member
}

# --- dbt: raw は読むだけ、staging / marts / ci に書く ---
resource "google_bigquery_dataset_iam_member" "dbt_raw_read" {
  dataset_id = google_bigquery_dataset.ds["raw"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.dbt.member
}

resource "google_bigquery_dataset_iam_member" "dbt_write" {
  for_each   = toset(["staging", "marts"])
  dataset_id = google_bigquery_dataset.ds[each.value].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.dbt.member
}

resource "google_bigquery_dataset_iam_member" "dbt_ci" {
  dataset_id = google_bigquery_dataset.ci.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.dbt.member
}

resource "google_project_iam_member" "job_user" {
  for_each = toset([google_service_account.ingestion.member, google_service_account.dbt.member])
  project  = var.project_id
  role     = "roles/bigquery.jobUser"
  member   = each.value
}

# --- オーケストレーター: ワークフロー起動と Cloud Run ジョブ実行 ---
resource "google_project_iam_member" "orchestrator" {
  for_each = toset(["roles/workflows.invoker", "roles/run.developer", "roles/logging.logWriter"])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.orchestrator.member
}

resource "google_service_account_iam_member" "orchestrator_act_as" {
  for_each           = { ingestion = google_service_account.ingestion.name, dbt = google_service_account.dbt.name }
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.orchestrator.member
}

# --- デプロイ: イメージの push と Cloud Run ジョブの更新 ---
resource "google_artifact_registry_repository_iam_member" "deployer_push" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.deployer.member
}

resource "google_project_iam_member" "deployer_run" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = google_service_account.deployer.member
}

resource "google_service_account_iam_member" "deployer_act_as" {
  for_each           = { ingestion = google_service_account.ingestion.name, dbt = google_service_account.dbt.name }
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.deployer.member
}
