# GitHub Actions から鍵ファイルなしで GCP に認証する（Workload Identity 連携）
# サービスアカウントキーを発行しないので、漏えいリスクがない

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  # 自分のリポジトリ以外からは認証できないようにする
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  github_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_service_account_iam_member" "github_wif" {
  for_each           = { deployer = google_service_account.deployer.name, dbt = google_service_account.dbt.name }
  service_account_id = each.value
  role               = "roles/iam.workloadIdentityUser"
  member             = local.github_principal
}
