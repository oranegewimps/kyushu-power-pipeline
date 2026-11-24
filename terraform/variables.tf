variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "github_repository" {
  description = "GitHub Actions からの認証を許可するリポジトリ（owner/name）"
  type        = string
}

variable "alert_email" {
  description = "パイプライン失敗時の通知先メールアドレス"
  type        = string
}

variable "schedule" {
  description = "日次実行の時刻（cron, JST）"
  type        = string
  default     = "0 6 * * *"
}
