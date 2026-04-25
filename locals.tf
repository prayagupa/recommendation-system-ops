locals {
  # ----------------------------------------------------------
  # Naming helpers
  # ----------------------------------------------------------
  name_prefix = "${var.project_name}-${var.environment}"

  # Common labels / tags attached to every resource
  common_labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }

  # ----------------------------------------------------------
  # Environment booleans (simplifies module conditionals)
  # ----------------------------------------------------------
  is_local = var.environment == "local"
  is_prod  = var.environment == "prod"

  # ----------------------------------------------------------
  # Internal Docker network name (local only)
  # ----------------------------------------------------------
  docker_network_name = "${local.name_prefix}-net"

  # ----------------------------------------------------------
  # Service hostnames (differ between environments)
  # ----------------------------------------------------------
  feature_store_host = local.is_local ? "recs-local-feature-store" : "redis.${var.gcp_region}.internal"
  serving_endpoint   = local.is_local ? "http://localhost:${var.serving_rest_port}/v1/models/recs" : module.gcp_serving[0].endpoint_url

  # ----------------------------------------------------------
  # Model artifact path
  # ----------------------------------------------------------
  model_artifacts_uri = local.is_local ? var.model_registry_local_path : "gs://${local.name_prefix}-artifacts/models"
}
