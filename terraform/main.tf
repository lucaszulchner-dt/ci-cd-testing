# Required GCP APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com"
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

data "google_project" "current" {
  project_id = var.project_id
}

# Artifact Registry Docker Repository
resource "google_artifact_registry_repository" "mock_app_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repo_name
  format        = "DOCKER"
  description   = "Docker repository for CI/CD test harness"

  depends_on = [google_project_service.apis]
}

# Cloud Run Runtime Service Account
resource "google_service_account" "mock_app_runtime" {
  project      = var.project_id
  account_id   = "mock-app-runtime"
  display_name = "Mock App Runtime Service Account"
}

# GitHub Actions Deployer Service Account
resource "google_service_account" "github_deployer" {
  project      = var.project_id
  account_id   = "mock-app-deployer"
  display_name = "GitHub Actions Deployer for Mock App"
}

# Workload Identity Federation (WIF) Pool
resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = var.project_id
  workload_identity_pool_id = "test-github-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for GitHub Actions test workflows"

  depends_on = [google_project_service.apis]
}

# Workload Identity Federation Provider (GitHub OIDC)
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "github-oidc"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow GitHub Actions to impersonate github-deployer via WIF
resource "google_service_account_iam_member" "deployer_wif_binding" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository_owner/${var.github_owner}"
}

# IAM Permissions for GitHub Deployer:
# 1. Cloud Run Admin to deploy and update services
resource "google_project_iam_member" "deployer_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

# 2. Artifact Registry Repository Admin to push, tag, and re-point moving tags (e.g. prod-latest)
resource "google_artifact_registry_repository_iam_member" "deployer_registry_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.mock_app_repo.name
  role       = "roles/artifactregistry.repoAdmin"
  member     = "serviceAccount:${google_service_account.github_deployer.email}"
}

# 3. Service Account User on Runtime SA (allows Cloud Run to attach the runtime identity)
resource "google_service_account_iam_member" "deployer_sa_user" {
  service_account_id = google_service_account.mock_app_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

# Cloud Run Service Agent permission to pull from Artifact Registry
resource "google_artifact_registry_repository_iam_member" "run_agent_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.mock_app_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.mock_app_runtime.email}"
}

# -------------------------------------------------------------
# 1. Cloud Run: Dev Environment (mock-app-dev)
# -------------------------------------------------------------
resource "google_cloud_run_v2_service" "mock_app_dev" {
  project  = var.project_id
  name     = var.dev_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.mock_app_runtime.email

    containers {
      # Bootstrap image allows terraform apply to succeed on Day 1 before first CI build
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "ENV_NAME"
        value = "dev"
      }
      env {
        name  = "APP_VERSION"
        value = "bootstrap"
      }
      env {
        name  = "GIT_SHA"
        value = "bootstrap"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
  }

  # John's Architecture Pattern: Terraform ignores image and env changes after Day 1
  # Application CI/CD pipeline deploys new revisions directly.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }

  depends_on = [google_project_service.apis]
}

# Allow public unauthenticated access to Dev for testing
resource "google_cloud_run_v2_service_iam_member" "dev_public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.mock_app_dev.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# -------------------------------------------------------------
# 2. Cloud Run: Prod Environment (mock-app-prod)
# -------------------------------------------------------------
resource "google_cloud_run_v2_service" "mock_app_prod" {
  project  = var.project_id
  name     = var.prod_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.mock_app_runtime.email

    containers {
      # Bootstrap image allows terraform apply to succeed on Day 1 before first release
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "ENV_NAME"
        value = "prod"
      }
      env {
        name  = "APP_VERSION"
        value = "bootstrap"
      }
      env {
        name  = "GIT_SHA"
        value = "bootstrap"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
  }

  # John's Architecture Pattern: Terraform ignores image and env changes after Day 1
  # Application CI/CD pipeline deploys new revisions directly.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }

  depends_on = [google_project_service.apis]
}

# Allow public unauthenticated access to Prod for testing
resource "google_cloud_run_v2_service_iam_member" "prod_public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.mock_app_prod.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
