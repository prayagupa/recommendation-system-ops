# ============================================================
# local.tfvars — Docker-based local development / demo
# Usage: terraform apply -var-file=envs/local.tfvars
# ============================================================

environment  = "local"
project_name = "recs"

# Feature Store
feature_store_redis_port  = 6379
feature_store_redis_image = "redis:7.2-alpine"

# Training
training_image        = "tensorflow/tensorflow:2.16.1"
training_port         = 6006    # TensorBoard
training_cpu_limit    = "2.0"
training_memory_limit = "4g"

# Serving
serving_image        = "tensorflow/serving:2.16.1"
serving_grpc_port    = 8500
serving_rest_port    = 8501
serving_memory_limit = "2g"

# Monitoring
prometheus_port        = 9090
grafana_port           = 3000
grafana_admin_password = "recs-local-admin"

# Model Registry
model_registry_local_path = "/tmp/recs-model-registry"
