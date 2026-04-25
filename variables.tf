# ============================================================
# Environment Toggle
# ============================================================
variable "environment" {
  description = "Deployment environment: 'local' for Docker-based demo, 'prod' for GCP"
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "prod"], var.environment)
    error_message = "environment must be one of: local, prod"
  }
}

variable "project_name" {
  description = "Short name for the recommendation system project (used in resource naming)"
  type        = string
  default     = "recs"
}

# ============================================================
# GCP (production only)
# ============================================================
variable "gcp_project_id" {
  description = "GCP Project ID (required when environment = prod)"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for production resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# ============================================================
# Feature Store
# ============================================================
variable "feature_store_redis_port" {
  description = "Redis port for the local feature store"
  type        = number
  default     = 6379
}

variable "feature_store_redis_image" {
  description = "Redis Docker image for the local feature store"
  type        = string
  default     = "redis:7.2-alpine"
}

# ============================================================
# Training Pipeline
# ============================================================
variable "training_image" {
  description = "Docker image used for the local training job"
  type        = string
  default     = "tensorflow/tensorflow:2.16.1"
}

variable "training_port" {
  description = "Port exposed by the training job container (TensorBoard)"
  type        = number
  default     = 6006
}

variable "training_cpu_limit" {
  description = "CPU limit for training container (local)"
  type        = string
  default     = "2.0"
}

variable "training_memory_limit" {
  description = "Memory limit for training container (local)"
  type        = string
  default     = "4g"
}

# Vertex AI (prod)
variable "vertex_training_machine_type" {
  description = "Vertex AI machine type for training"
  type        = string
  default     = "n1-standard-8"
}

variable "vertex_training_accelerator_type" {
  description = "Vertex AI accelerator type (GPU) for training"
  type        = string
  default     = "NVIDIA_TESLA_T4"
}

variable "vertex_training_accelerator_count" {
  description = "Number of accelerators for Vertex AI training"
  type        = number
  default     = 1
}

# ============================================================
# Model Serving
# ============================================================
variable "serving_image" {
  description = "Docker image used for the local model-serving container"
  type        = string
  default     = "tensorflow/serving:2.16.1"
}

variable "serving_grpc_port" {
  description = "gRPC port for TF Serving"
  type        = number
  default     = 8500
}

variable "serving_rest_port" {
  description = "REST port for TF Serving"
  type        = number
  default     = 8501
}

variable "serving_memory_limit" {
  description = "Memory limit for the local serving container"
  type        = string
  default     = "2g"
}

# Cloud Run (prod)
variable "cloud_run_min_instances" {
  description = "Minimum Cloud Run instances for serving"
  type        = number
  default     = 1
}

variable "cloud_run_max_instances" {
  description = "Maximum Cloud Run instances for serving"
  type        = number
  default     = 10
}

variable "cloud_run_cpu" {
  description = "CPU allocation per Cloud Run instance"
  type        = string
  default     = "2"
}

variable "cloud_run_memory" {
  description = "Memory allocation per Cloud Run instance"
  type        = string
  default     = "4Gi"
}

# ============================================================
# Monitoring
# ============================================================
variable "prometheus_port" {
  description = "Port exposed by local Prometheus"
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "Port exposed by local Grafana"
  type        = number
  default     = 3000
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "recs-local-admin"
}

# ============================================================
# Storage / Model Registry
# ============================================================
variable "model_registry_local_path" {
  description = "Host path for the local model registry (Docker volume mount)"
  type        = string
  default     = "/tmp/recs-model-registry"
}

variable "gcs_bucket_location" {
  description = "GCS bucket location for model artifacts (prod)"
  type        = string
  default     = "US"
}
