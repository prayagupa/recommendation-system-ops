# ============================================================
# Root outputs
# ============================================================

output "environment" {
  description = "Active deployment environment"
  value       = var.environment
}

output "feature_store_connection" {
  description = "Redis feature store connection string"
  value       = "${local.feature_store_host}:${var.feature_store_redis_port}"
}

output "model_artifacts_uri" {
  description = "Where model artifacts are stored"
  value       = local.model_artifacts_uri
}

output "serving_endpoint" {
  description = "Recommendation model REST endpoint"
  value       = local.serving_endpoint
}

output "tensorboard_url" {
  description = "TensorBoard URL (local only)"
  value       = local.is_local ? "http://localhost:${var.training_port}" : "See Vertex AI console"
}

output "grafana_url" {
  description = "Grafana dashboard URL (local only)"
  value       = local.is_local ? "http://localhost:${var.grafana_port}" : "See Cloud Monitoring"
}

output "prometheus_url" {
  description = "Prometheus URL (local only)"
  value       = local.is_local ? "http://localhost:${var.prometheus_port}" : "See Cloud Monitoring"
}
