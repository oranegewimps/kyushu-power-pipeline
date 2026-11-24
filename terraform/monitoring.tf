# ワークフローが失敗したらメールで通知する

resource "google_monitoring_notification_channel" "email" {
  display_name = "パイプライン通知"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
  depends_on = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "workflow_failed" {
  display_name = "日次パイプラインの失敗"
  combiner     = "OR"

  conditions {
    display_name = "Workflows の実行が失敗した"
    condition_matched_log {
      filter = <<-EOT
        resource.type="workflows.googleapis.com/Workflow"
        resource.labels.workflow_id="${google_workflows_workflow.daily.name}"
        severity>=ERROR
      EOT
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
    auto_close = "86400s"
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content   = "Cloud Run ジョブ（ingestion / dbt-build）のログを確認してください。"
    mime_type = "text/markdown"
  }
}
