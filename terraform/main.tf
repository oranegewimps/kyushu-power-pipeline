locals {
  apis = [
    "run.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
  ]
  # 初回はダミーのイメージで作り、以降のイメージ更新は GitHub Actions が行う
  placeholder_image = "us-docker.pkg.dev/cloudrun/container/job:latest"
  image             = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/pipeline:latest"
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {}

resource "google_artifact_registry_repository" "app" {
  repository_id = "pipeline"
  location      = var.region
  format        = "DOCKER"
  description   = "取り込み・dbt 用のコンテナイメージ"

  cleanup_policies {
    id     = "keep-latest-5"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  depends_on = [google_project_service.apis]
}
