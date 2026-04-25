# ==============================================================
# Model Registry / Artifact Storage Module
# Local directory for local; GCS bucket + Artifact Registry for GCP prod
# ==============================================================

variable "environment"         {}
variable "name_prefix"         {}
variable "common_labels"       { type = map(string) }
variable "local_registry_path" { default = "/tmp/recs-model-registry" }
variable "gcp_project_id"      { default = "" }
variable "gcp_region"          { default = "us-central1" }
variable "bucket_location"     { default = "US" }

locals {
  is_local    = var.environment == "local"
  bucket_name = "${var.name_prefix}-artifacts"
}

# ------------------------------------------------------------------
# LOCAL: Create the directory on the host via local-exec
# ------------------------------------------------------------------
resource "terraform_data" "local_registry" {
  count = local.is_local ? 1 : 0

  provisioner "local-exec" {
    command = "mkdir -p ${var.local_registry_path}/models ${var.local_registry_path}/checkpoints ${var.local_registry_path}/logs"
  }
}

resource "local_file" "registry_readme" {
  count    = local.is_local ? 1 : 0
  filename = "${var.local_registry_path}/README.md"
  content  = <<-EOF
    # Local Model Registry
    Managed by Terraform (recs-ops-terraform).

    ## Directory layout
    ```
    models/         – SavedModel exports keyed by <model_name>/<version>/
    checkpoints/    – Training checkpoints
    logs/           – TensorBoard event files
    ```
  EOF
}

# ------------------------------------------------------------------
# PROD: GCS bucket for model artifacts
# ------------------------------------------------------------------
resource "google_storage_bucket" "artifacts" {
  count = local.is_local ? 0 : 1

  name          = local.bucket_name
  project       = var.gcp_project_id
  location      = var.bucket_location
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                = 365
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
  labels                      = var.common_labels
}

# GCP Artifact Registry for Docker images
resource "google_artifact_registry_repository" "recs_images" {
  count = local.is_local ? 0 : 1

  repository_id = "${var.name_prefix}-images"
  location      = var.gcp_region
  format        = "DOCKER"
  project       = var.gcp_project_id

  description = "Recommendation system training & serving Docker images"
  labels      = var.common_labels
}

# ------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------
output "artifacts_uri" {
  description = "URI for model artifact storage"
  value       = local.is_local ? var.local_registry_path : "gs://${local.bucket_name}/models"
}

output "checkpoints_uri" {
  description = "URI for training checkpoints"
  value       = local.is_local ? "${var.local_registry_path}/checkpoints" : "gs://${local.bucket_name}/checkpoints"
}

output "logs_uri" {
  description = "URI for training logs"
  value       = local.is_local ? "${var.local_registry_path}/logs" : "gs://${local.bucket_name}/logs"
}

output "docker_registry" {
  description = "Docker image registry"
  value       = local.is_local ? "local" : "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.name_prefix}-images"
}
