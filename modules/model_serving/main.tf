# ==============================================================
# Model Serving Module
# Local: TensorFlow Serving container
# GCP:   Cloud Run service
# ==============================================================

variable "environment"             {}
variable "name_prefix"             {}
variable "common_labels"           { type = map(string) }
variable "docker_network_name"     { default = "" }
variable "model_artifacts_uri"     {}
variable "serving_image"           { default = "tensorflow/serving:2.16.1" }
variable "serving_grpc_port"       { default = 8500 }
variable "serving_rest_port"       { default = 8501 }
variable "serving_memory_limit"    { default = "2g" }
variable "gcp_project_id"          { default = "" }
variable "gcp_region"              { default = "us-central1" }
variable "cloud_run_min_instances" { default = 1 }
variable "cloud_run_max_instances" { default = 10 }
variable "cloud_run_cpu"           { default = "2" }
variable "cloud_run_memory"        { default = "4Gi" }

locals {
  is_local       = var.environment == "local"
  container_name = "${var.name_prefix}-serving"
}

# ------------------------------------------------------------------
# LOCAL: TF Serving container
# ------------------------------------------------------------------
resource "docker_image" "tf_serving" {
  count        = local.is_local ? 1 : 0
  name         = var.serving_image
  keep_locally = true
}

resource "docker_container" "tf_serving" {
  count   = local.is_local ? 1 : 0
  name    = local.container_name
  image   = docker_image.tf_serving[0].image_id
  restart = "unless-stopped"

  # gRPC
  ports {
    internal = 8500
    external = var.serving_grpc_port
  }

  # REST
  ports {
    internal = 8501
    external = var.serving_rest_port
  }

  networks_advanced {
    name = var.docker_network_name
  }

  # Mount model registry so TF Serving can hot-reload new versions
  volumes {
    host_path      = "${var.model_artifacts_uri}/models"
    container_path = "/models"
  }

  memory = tonumber(trimspace(replace(var.serving_memory_limit, "g", ""))) * 1024

  env = [
    "MODEL_NAME=recs",
    "TF_CPP_MIN_LOG_LEVEL=2",
  ]

  command = [
    "--model_config_file=/models/models.config",
    "--model_config_file_poll_wait_seconds=30",
    "--enable_batching=true",
    "--batching_parameters_file=/models/batching.config",
    "--monitoring_config_file=/models/monitoring.config",
  ]

  healthcheck {
    test     = ["CMD-SHELL", "curl -sf http://localhost:8501/v1/models/recs || exit 1"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }

  labels {
    label = "project"
    value = var.name_prefix
  }
}

# ------------------------------------------------------------------
# PROD: Cloud Run service
# ------------------------------------------------------------------

# Service account for Cloud Run
resource "google_service_account" "serving_sa" {
  count        = local.is_local ? 0 : 1
  account_id   = "${var.name_prefix}-serving-sa"
  display_name = "Recs Serving Service Account"
  project      = var.gcp_project_id
}

# Allow Cloud Run SA to read from GCS
resource "google_project_iam_member" "serving_gcs_reader" {
  count   = local.is_local ? 0 : 1
  project = var.gcp_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.serving_sa[0].email}"
}

resource "google_cloud_run_v2_service" "recs_serving" {
  count    = local.is_local ? 0 : 1
  name     = "${var.name_prefix}-serving"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    service_account = google_service_account.serving_sa[0].email

    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    containers {
      image = var.serving_image

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle = false   # keep CPU during request only
      }

      ports {
        name           = "h2c"   # gRPC
        container_port = 8500
      }

      env {
        name  = "MODEL_NAME"
        value = "recs"
      }

      env {
        name  = "GCS_MODEL_PATH"
        value = var.model_artifacts_uri
      }

      startup_probe {
        http_get {
          path = "/v1/models/recs"
          port = 8501
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 6
      }

      liveness_probe {
        http_get {
          path = "/v1/models/recs"
          port = 8501
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  labels = var.common_labels
}

# Allow unauthenticated invocations (swap for internal-only in real prod)
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = local.is_local ? 0 : 1
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.recs_serving[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------
output "endpoint_url" {
  description = "Model serving REST endpoint"
  value       = local.is_local ? "http://localhost:${var.serving_rest_port}/v1/models/recs" : google_cloud_run_v2_service.recs_serving[0].uri
}

output "grpc_endpoint" {
  description = "Model serving gRPC endpoint"
  value       = local.is_local ? "localhost:${var.serving_grpc_port}" : "${trimprefix(google_cloud_run_v2_service.recs_serving[0].uri, "https://")}:443"
}
