output "workload_identity_provider" {
  description = "GitHub Actions の google-github-actions/auth に渡す値"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  value = google_service_account.deployer.email
}

output "dbt_service_account" {
  value = google_service_account.dbt.email
}

output "image" {
  value = local.image
}

output "raw_bucket" {
  value = google_storage_bucket.raw.name
}
