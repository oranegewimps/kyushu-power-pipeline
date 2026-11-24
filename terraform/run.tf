# 同じコンテナイメージを、引数を変えて2つのジョブとして使う

resource "google_cloud_run_v2_job" "ingestion" {
  name                = "ingestion"
  location            = var.region
  deletion_protection = false

  template {
    task_count = 1
    template {
      service_account = google_service_account.ingestion.email
      timeout         = "1800s"
      max_retries     = 1
      containers {
        image   = local.placeholder_image
        command = ["python", "-m", "ingestion.main"]
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "RAW_BUCKET"
          value = google_storage_bucket.raw.name
        }
        resources {
          limits = { cpu = "1", memory = "512Mi" }
        }
      }
    }
  }

  lifecycle {
    # イメージの更新は GitHub Actions（gcloud）が行うため、Terraform では差分として扱わない
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
  depends_on = [google_project_service.apis]
}

# 取り込み・dbt の後に、元CSV ↔ BigQuery ↔ dbt の集計結果を突き合わせる
resource "google_cloud_run_v2_job" "reconcile" {
  name                = "reconcile"
  location            = var.region
  deletion_protection = false

  template {
    task_count = 1
    template {
      service_account = google_service_account.ingestion.email
      timeout         = "900s"
      max_retries     = 0
      containers {
        image   = local.placeholder_image
        command = ["python", "-m", "ingestion.reconcile", "--source-samples", "1"]
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "RAW_BUCKET"
          value = google_storage_bucket.raw.name
        }
        resources {
          limits = { cpu = "1", memory = "512Mi" }
        }
      }
    }
  }

  lifecycle {
    # イメージの更新は GitHub Actions（gcloud）が行うため、Terraform では差分として扱わない
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_job" "dbt" {
  name                = "dbt-build"
  location            = var.region
  deletion_protection = false

  template {
    task_count = 1
    template {
      service_account = google_service_account.dbt.email
      timeout         = "1800s"
      max_retries     = 0
      containers {
        image   = local.placeholder_image
        command = ["dbt", "build", "--project-dir", "dbt", "--profiles-dir", "dbt", "--target", "prod"]
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        resources {
          limits = { cpu = "1", memory = "1Gi" }
        }
      }
    }
  }

  lifecycle {
    # イメージの更新は GitHub Actions（gcloud）が行うため、Terraform では差分として扱わない
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
  depends_on = [google_project_service.apis]
}
