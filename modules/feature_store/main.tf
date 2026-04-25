# ==============================================================
# Feature Store Module
# Redis for local; Cloud Memorystore (Redis) for GCP prod
# ==============================================================

variable "environment"         {}
variable "name_prefix"         {}
variable "common_labels"       { type = map(string) }
variable "docker_network_name" { default = "" }
variable "redis_image"         { default = "redis:7.2-alpine" }
variable "redis_port"          { default = 6379 }
variable "gcp_project_id"      { default = "" }
variable "gcp_region"          { default = "us-central1" }

locals {
  is_local        = var.environment == "local"
  container_name  = "${var.name_prefix}-feature-store"
}

# ------------------------------------------------------------------
# LOCAL: Redis container
# ------------------------------------------------------------------
resource "docker_image" "redis" {
  count = local.is_local ? 1 : 0
  name  = var.redis_image

  keep_locally = true
}

resource "docker_container" "redis" {
  count = local.is_local ? 1 : 0
  name  = local.container_name
  image = docker_image.redis[0].image_id

  restart = "unless-stopped"

  ports {
    internal = 6379
    external = var.redis_port
  }

  networks_advanced {
    name = var.docker_network_name
  }

  command = [
    "redis-server",
    "--maxmemory", "512mb",
    "--maxmemory-policy", "allkeys-lru",
    "--save", "60", "1",
  ]

  volumes {
    volume_name    = docker_volume.redis_data[0].name
    container_path = "/data"
  }

  healthcheck {
    test         = ["CMD", "redis-cli", "ping"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "5s"
  }

  labels {
    label = "project"
    value = var.name_prefix
  }
}

resource "docker_volume" "redis_data" {
  count = local.is_local ? 1 : 0
  name  = "${local.container_name}-data"
}

# ------------------------------------------------------------------
# PROD: Cloud Memorystore for Redis
# ------------------------------------------------------------------
resource "google_redis_instance" "feature_store" {
  count = local.is_local ? 0 : 1

  name           = "${var.name_prefix}-feature-store"
  tier           = "STANDARD_HA"
  memory_size_gb = 4
  region         = var.gcp_region
  project        = var.gcp_project_id

  redis_version = "REDIS_7_0"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  labels = var.common_labels
}

# ------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------
output "host" {
  description = "Feature store Redis host"
  value = local.is_local ? local.container_name : google_redis_instance.feature_store[0].host
}

output "port" {
  description = "Feature store Redis port"
  value = var.redis_port
}
