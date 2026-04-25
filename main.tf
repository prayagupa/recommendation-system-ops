# ============================================================
# Provider configuration
# ============================================================

# Docker provider — always configured so `terraform init` works
# regardless of environment; individual resources are gated by count/for_each
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# GCP providers — only used when environment = prod
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# ============================================================
# Shared infrastructure — Docker network (local)
# ============================================================
resource "docker_network" "recs_net" {
  count = local.is_local ? 1 : 0
  name  = local.docker_network_name

  labels {
    label = "project"
    value = var.project_name
  }
}

# ============================================================
# Module: Feature Store
# ============================================================
module "feature_store" {
  source = "./modules/feature_store"

  environment         = var.environment
  name_prefix         = local.name_prefix
  common_labels       = local.common_labels
  docker_network_name = local.is_local ? docker_network[0].name : ""

  # Local
  redis_image = var.feature_store_redis_image
  redis_port  = var.feature_store_redis_port

  # GCP
  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region

  depends_on = [docker_network.recs_net]
}

# ============================================================
# Module: Model Registry / Artifact Storage
# ============================================================
module "model_registry" {
  source = "./modules/model_registry"

  environment         = var.environment
  name_prefix         = local.name_prefix
  common_labels       = local.common_labels
  local_registry_path = var.model_registry_local_path

  # GCP
  gcp_project_id   = var.gcp_project_id
  gcp_region       = var.gcp_region
  bucket_location  = var.gcs_bucket_location
}

# ============================================================
# Module: Training Pipeline
# ============================================================
module "training_pipeline" {
  source = "./modules/training_pipeline"

  environment         = var.environment
  name_prefix         = local.name_prefix
  common_labels       = local.common_labels
  docker_network_name = local.is_local ? docker_network.recs_net[0].name : ""
  model_artifacts_uri = local.model_artifacts_uri

  # Local
  training_image        = var.training_image
  training_port         = var.training_port
  training_cpu_limit    = var.training_cpu_limit
  training_memory_limit = var.training_memory_limit
  feature_store_host    = local.feature_store_host
  feature_store_port    = var.feature_store_redis_port

  # GCP / Vertex AI
  gcp_project_id                    = var.gcp_project_id
  gcp_region                        = var.gcp_region
  vertex_training_machine_type      = var.vertex_training_machine_type
  vertex_training_accelerator_type  = var.vertex_training_accelerator_type
  vertex_training_accelerator_count = var.vertex_training_accelerator_count

  depends_on = [module.feature_store, module.model_registry]
}

# ============================================================
# Module: Model Serving
# ============================================================
module "model_serving" {
  source = "./modules/model_serving"

  environment         = var.environment
  name_prefix         = local.name_prefix
  common_labels       = local.common_labels
  docker_network_name = local.is_local ? docker_network.recs_net[0].name : ""
  model_artifacts_uri = local.model_artifacts_uri

  # Local
  serving_image        = var.serving_image
  serving_grpc_port    = var.serving_grpc_port
  serving_rest_port    = var.serving_rest_port
  serving_memory_limit = var.serving_memory_limit

  # GCP / Cloud Run
  gcp_project_id          = var.gcp_project_id
  gcp_region              = var.gcp_region
  cloud_run_min_instances = var.cloud_run_min_instances
  cloud_run_max_instances = var.cloud_run_max_instances
  cloud_run_cpu           = var.cloud_run_cpu
  cloud_run_memory        = var.cloud_run_memory

  depends_on = [module.model_registry]
}

# ============================================================
# Module: Monitoring (Prometheus + Grafana)
# ============================================================
module "monitoring" {
  source = "./modules/monitoring"

  environment         = var.environment
  name_prefix         = local.name_prefix
  common_labels       = local.common_labels
  docker_network_name = local.is_local ? docker_network.recs_net[0].name : ""

  # Local
  prometheus_port        = var.prometheus_port
  grafana_port           = var.grafana_port
  grafana_admin_password = var.grafana_admin_password

  # Scrape targets (local containers)
  scrape_targets = local.is_local ? [
    "${local.name_prefix}-training:${var.training_port}",
    "${local.name_prefix}-serving:${var.serving_grpc_port}",
  ] : []

  # GCP — Cloud Monitoring is used in prod; this module becomes a no-op
  gcp_project_id = var.gcp_project_id

  depends_on = [module.training_pipeline, module.model_serving]
}

# ============================================================
# Reference to GCP serving endpoint (prod only) — used in locals
# ============================================================
module "gcp_serving" {
  count  = local.is_prod ? 1 : 0
  source = "./modules/model_serving"

  environment         = var.environment
  name_prefix         = local.name_prefix
  common_labels       = local.common_labels
  docker_network_name = ""
  model_artifacts_uri = local.model_artifacts_uri

  serving_image        = var.serving_image
  serving_grpc_port    = var.serving_grpc_port
  serving_rest_port    = var.serving_rest_port
  serving_memory_limit = var.serving_memory_limit

  gcp_project_id          = var.gcp_project_id
  gcp_region              = var.gcp_region
  cloud_run_min_instances = var.cloud_run_min_instances
  cloud_run_max_instances = var.cloud_run_max_instances
  cloud_run_cpu           = var.cloud_run_cpu
  cloud_run_memory        = var.cloud_run_memory
}
