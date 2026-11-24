# Cloud Build 専用のサービスアカウント。
# 新しいプロジェクトでは既定のビルド用アカウント（Compute Engine の既定SA）が無いため、明示的に用意する

resource "google_service_account" "builder" {
  account_id   = "sa-cloudbuild"
  display_name = "Cloud Build（イメージのビルド）"
  depends_on   = [google_project_service.apis]
}

resource "google_artifact_registry_repository_iam_member" "builder_push" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.builder.member
}

resource "google_project_iam_member" "builder_log" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.builder.member
}

# ソース（tar）の置き場所。gcloud builds submit がアップロードする
resource "google_storage_bucket" "build_source" {
  name                        = "${var.project_id}-build-source"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "builder_source" {
  bucket = google_storage_bucket.build_source.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.builder.member
}

# GitHub Actions のデプロイ用SAが、ビルドを起動してビルド用SAとして実行できるように
# logging.viewer は、ビルドのログ（Cloud Logging のみに出力）を GitHub Actions 上に流すため
resource "google_project_iam_member" "deployer_build" {
  for_each = toset(["roles/cloudbuild.builds.editor", "roles/serviceusage.serviceUsageConsumer", "roles/logging.viewer"])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.deployer.member
}

resource "google_storage_bucket_iam_member" "deployer_source" {
  bucket = google_storage_bucket.build_source.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.deployer.member
}

# gcloud builds submit はアップロード前にバケットの存在を確認する（storage.buckets.get）。
# objectAdmin には含まれないため、このバケットに限って付与する
resource "google_storage_bucket_iam_member" "deployer_source_bucket" {
  bucket = google_storage_bucket.build_source.name
  role   = "roles/storage.legacyBucketReader"
  member = google_service_account.deployer.member
}

resource "google_service_account_iam_member" "deployer_act_as_builder" {
  service_account_id = google_service_account.builder.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.deployer.member
}

output "builder_service_account" {
  value = google_service_account.builder.email
}

output "build_source_bucket" {
  value = google_storage_bucket.build_source.name
}
