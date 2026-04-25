# ==============================================================
# Training Pipeline Module
# Local: TensorFlow container running a training script
#        + TensorBoard sidecar
# GCP:   Vertex AI Custom Training Job
# ==============================================================

variable "environment"                     {}
variable "name_prefix"                     {}
variable "common_labels"                   { type = map(string) }
variable "docker_network_name"             { default = "" }
variable "model_artifacts_uri"             {}
variable "training_image"                  { default = "tensorflow/tensorflow:2.16.1" }
variable "training_port"                   { default = 6006 }
variable "training_cpu_limit"              { default = "2.0" }
variable "training_memory_limit"           { default = "4g" }
variable "feature_store_host"              {}
variable "feature_store_port"              { default = 6379 }
variable "gcp_project_id"                  { default = "" }
variable "gcp_region"                      { default = "us-central1" }
variable "vertex_training_machine_type"    { default = "n1-standard-8" }
variable "vertex_training_accelerator_type"  { default = "NVIDIA_TESLA_T4" }
variable "vertex_training_accelerator_count" { default = 1 }

locals {
  is_local = var.environment == "local"

  # Environment variables injected into the training container
  training_env = {
    FEATURE_STORE_HOST    = var.feature_store_host
    FEATURE_STORE_PORT    = tostring(var.feature_store_port)
    MODEL_OUTPUT_DIR      = var.model_artifacts_uri
    PYTHONUNBUFFERED      = "1"
    TF_CPP_MIN_LOG_LEVEL  = "2"
  }
}

# ------------------------------------------------------------------
# LOCAL: TensorFlow training container
# ------------------------------------------------------------------
resource "docker_image" "training" {
  count        = local.is_local ? 1 : 0
  name         = var.training_image
  keep_locally = true
}

resource "docker_container" "training" {
  count   = local.is_local ? 1 : 0
  name    = "${var.name_prefix}-training"
  image   = docker_image.training[0].image_id
  restart = "no"               # training jobs run once

  # Expose TensorBoard
  ports {
    internal = 6006
    external = var.training_port
  }

  networks_advanced {
    name = var.docker_network_name
  }

  # Mount the local model registry
  volumes {
    host_path      = var.model_artifacts_uri
    container_path = "/model-registry"
  }

  # Seed training script from the configs directory
  volumes {
    host_path      = "${path.root}/configs/training"
    container_path = "/workspace"
  }

  env = [for k, v in local.training_env : "${k}=${v}"]

  # Resource constraints
  cpu_shares = 1024 * tonumber(var.training_cpu_limit)
  memory     = tonumber(trimspace(replace(var.training_memory_limit, "g", ""))) * 1024

  # Run TensorBoard + launch training script
  command = [
    "bash", "-c",
    <<-BASH
      pip install --quiet redis tensorflow-recommenders && \
      tensorboard --logdir /model-registry/logs --host 0.0.0.0 &
      python /workspace/train.py
    BASH
  ]

  labels {
    label = "project"
    value = var.name_prefix
  }
}

# ------------------------------------------------------------------
# PROD: Vertex AI Custom Training Job definition
# (The job itself is triggered by CI/CD, not Terraform apply)
# ------------------------------------------------------------------
resource "google_vertex_ai_dataset" "recs_events" {
  count        = local.is_local ? 0 : 1
  display_name = "${var.name_prefix}-user-events"
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region       = var.gcp_region
  project      = var.gcp_project_id

  labels = var.common_labels
}

# Vertex AI Pipeline (Kubeflow / Managed Pipelines) placeholder
resource "google_vertex_ai_pipeline_job" "training_pipeline" {
  count        = local.is_local ? 0 : 1
  display_name = "${var.name_prefix}-training-pipeline"
  location     = var.gcp_region
  project      = var.gcp_project_id

  pipeline_spec = jsonencode({
    pipelineInfo = { name = "${var.name_prefix}-training" }
    root = {
      dag = {
        tasks = {
          training-task = {
            cachingOptions = { enableCache = true }
            componentRef   = { name = "comp-training-task" }
            inputs = {
              parameters = {
                machine_type        = { runtimeValue = { constant = var.vertex_training_machine_type } }
                accelerator_type    = { runtimeValue = { constant = var.vertex_training_accelerator_type } }
                accelerator_count   = { runtimeValue = { constant = tostring(var.vertex_training_accelerator_count) } }
                model_output_gcs    = { runtimeValue = { constant = var.model_artifacts_uri } }
                feature_store_host  = { runtimeValue = { constant = var.feature_store_host } }
              }
            }
            taskInfo = { name = "training-task" }
          }
        }
      }
    }
    components = {}
  })

  labels = var.common_labels
}

# ------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------
output "tensorboard_url" {
  description = "TensorBoard URL"
  value       = local.is_local ? "http://localhost:${var.training_port}" : "https://us-central1.tensorboard.googleusercontent.com"
}

output "training_container_name" {
  description = "Local training container name"
  value       = local.is_local ? docker_container.training[0].name : "n/a (Vertex AI)"
}
