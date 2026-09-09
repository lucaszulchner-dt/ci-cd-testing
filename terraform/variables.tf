variable "project_id" {
  description = "GCP Project ID for the sandbox environment"
  type        = string
  default     = "lucas--rios-sandbox"
}

variable "region" {
  description = "GCP Region for Cloud Run and Artifact Registry"
  type        = string
  default     = "europe-west1"
}

variable "artifact_repo_name" {
  description = "Name of the Artifact Registry Docker repository"
  type        = string
  default     = "mock-app-repo"
}

variable "dev_service_name" {
  description = "Name of the Dev Cloud Run service"
  type        = string
  default     = "mock-app-dev"
}

variable "prod_service_name" {
  description = "Name of the Prod Cloud Run service"
  type        = string
  default     = "mock-app-prod"
}

variable "github_owner" {
  description = "GitHub user or organization allowed to authenticate via WIF"
  type        = string
  default     = "lucaszulchner-dt"
}
