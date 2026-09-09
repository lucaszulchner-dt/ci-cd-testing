output "dev_service_url" {
  description = "Public URL for Dev Cloud Run service"
  value       = google_cloud_run_v2_service.mock_app_dev.uri
}

output "prod_service_url" {
  description = "Public URL for Prod Cloud Run service"
  value       = google_cloud_run_v2_service.mock_app_prod.uri
}

output "artifact_registry_repo_path" {
  description = "Base Docker path in Artifact Registry (vars.GAR_REGISTRY)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.mock_app_repo.repository_id}"
}

output "deployer_service_account_email" {
  description = "Deployer SA email (vars.WIF_SERVICE_ACCOUNT)"
  value       = google_service_account.github_deployer.email
}

output "runtime_service_account_email" {
  description = "Service account email attached to Cloud Run services"
  value       = google_service_account.mock_app_runtime.email
}

# --- Exact GitHub Actions Variables to configure in Repository Settings ---

output "github_action_vars" {
  description = "Map of all variables needed by GitHub Actions (identical to real repo)"
  value = {
    WIF_PROVIDER        = "projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_provider.workload_identity_pool_provider_id}"
    WIF_SERVICE_ACCOUNT = google_service_account.github_deployer.email
    GCP_REGION          = var.region
    GAR_REGISTRY        = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.mock_app_repo.repository_id}"
    GCP_PROJECT_ID      = var.project_id
    SERVICE_NAME_DEV    = google_cloud_run_v2_service.mock_app_dev.name
    SERVICE_NAME_PROD   = google_cloud_run_v2_service.mock_app_prod.name
  }
}
