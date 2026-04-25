# ==============================================================
# Monitoring Module
# Local: Prometheus + Grafana containers
# GCP:   Cloud Monitoring dashboards + alerting policies
# ==============================================================

variable "environment"            {}
variable "name_prefix"            {}
variable "common_labels"          { type = map(string) }
variable "docker_network_name"    { default = "" }
variable "prometheus_port"        { default = 9090 }
variable "grafana_port"           { default = 3000 }
variable "grafana_admin_password" { default = "admin" }
variable "scrape_targets"         { type = list(string); default = [] }
variable "gcp_project_id"         { default = "" }

locals {
  is_local            = var.environment == "local"
  prometheus_cfg_path = "${path.root}/configs/monitoring/prometheus.yml"
  grafana_cfg_path    = "${path.root}/configs/monitoring/grafana"
}

# ------------------------------------------------------------------
# LOCAL: Generate Prometheus config
# ------------------------------------------------------------------
resource "local_file" "prometheus_config" {
  count    = local.is_local ? 1 : 0
  filename = local.prometheus_cfg_path
  content  = templatefile("${path.module}/templates/prometheus.yml.tpl", {
    scrape_targets = var.scrape_targets
    name_prefix    = var.name_prefix
  })
}

# ------------------------------------------------------------------
# LOCAL: Prometheus container
# ------------------------------------------------------------------
resource "docker_image" "prometheus" {
  count        = local.is_local ? 1 : 0
  name         = "prom/prometheus:v2.51.2"
  keep_locally = true
}

resource "docker_container" "prometheus" {
  count   = local.is_local ? 1 : 0
  name    = "${var.name_prefix}-prometheus"
  image   = docker_image.prometheus[0].image_id
  restart = "unless-stopped"

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  networks_advanced {
    name = var.docker_network_name
  }

  volumes {
    host_path      = dirname(local.prometheus_cfg_path)
    container_path = "/etc/prometheus"
  }

  volumes {
    volume_name    = docker_volume.prometheus_data[0].name
    container_path = "/prometheus"
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=15d",
    "--web.enable-lifecycle",
  ]

  depends_on = [local_file.prometheus_config]
}

resource "docker_volume" "prometheus_data" {
  count = local.is_local ? 1 : 0
  name  = "${var.name_prefix}-prometheus-data"
}

# ------------------------------------------------------------------
# LOCAL: Grafana container
# ------------------------------------------------------------------
resource "docker_image" "grafana" {
  count        = local.is_local ? 1 : 0
  name         = "grafana/grafana:10.4.2"
  keep_locally = true
}

resource "docker_container" "grafana" {
  count   = local.is_local ? 1 : 0
  name    = "${var.name_prefix}-grafana"
  image   = docker_image.grafana[0].image_id
  restart = "unless-stopped"

  ports {
    internal = 3000
    external = var.grafana_port
  }

  networks_advanced {
    name = var.docker_network_name
  }

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards/recs-overview.json",
  ]

  volumes {
    host_path      = local.grafana_cfg_path
    container_path = "/etc/grafana/provisioning"
  }

  volumes {
    volume_name    = docker_volume.grafana_data[0].name
    container_path = "/var/lib/grafana"
  }

  labels {
    label = "project"
    value = var.name_prefix
  }
}

resource "docker_volume" "grafana_data" {
  count = local.is_local ? 1 : 0
  name  = "${var.name_prefix}-grafana-data"
}

# ------------------------------------------------------------------
# PROD: Cloud Monitoring dashboard
# ------------------------------------------------------------------
resource "google_monitoring_dashboard" "recs_dashboard" {
  count        = local.is_local ? 0 : 1
  project      = var.gcp_project_id
  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} - Recommendation System"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Serving Request Latency (p99)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\""
                }
              }
            }]
          }
        },
        {
          title = "Serving QPS"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\""
                }
              }
            }]
          }
        },
      ]
    }
  })
}

# Uptime check for serving endpoint
resource "google_monitoring_uptime_check_config" "serving_health" {
  count        = local.is_local ? 0 : 1
  project      = var.gcp_project_id
  display_name = "${var.name_prefix}-serving-health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/v1/models/recs"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.gcp_project_id
      host       = "recs-serving.example.com"
    }
  }
}

# ------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------
output "prometheus_url" {
  value = local.is_local ? "http://localhost:${var.prometheus_port}" : "https://console.cloud.google.com/monitoring"
}

output "grafana_url" {
  value = local.is_local ? "http://localhost:${var.grafana_port}" : "https://console.cloud.google.com/monitoring/dashboards"
}
