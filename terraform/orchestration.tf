# Scheduler（毎朝）→ Workflows → 取り込み → dbt の順に実行

resource "google_workflows_workflow" "daily" {
  name            = "daily-pipeline"
  region          = var.region
  description     = "取り込み → dbt build → 整合性チェックを順に実行する"
  service_account = google_service_account.orchestrator.id
  source_contents = templatefile("${path.module}/workflow.yaml", {
    project = var.project_id
    region  = var.region
  })
  depends_on = [google_project_service.apis]
}

resource "google_cloud_scheduler_job" "daily" {
  name      = "daily-pipeline"
  region    = var.region
  schedule  = var.schedule
  time_zone = "Asia/Tokyo"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.daily.id}/executions"
    body        = base64encode("{}")
    oauth_token {
      service_account_email = google_service_account.orchestrator.email
    }
  }
  depends_on = [google_project_service.apis]
}
