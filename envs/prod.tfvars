# ============================================================
# prod.tfvars — GCP production environment
# Usage: terraform apply -var-file=envs/prod.tfvars
# ============================================================

environment  = "prod"
project_name = "recs"

# ── GCP ───────────────────────────────────────────────────
gcp_project_id = "your-gcp-project-id"   # ← REPLACE
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"

# ── Feature Store (Cloud Memorystore) ─────────────────────
feature_store_redis_port = 6379

# ── Vertex AI Training ────────────────────────────────────
vertex_training_machine_type       = "n1-standard-8"
vertex_training_accelerator_type   = "NVIDIA_TESLA_T4"
vertex_training_accelerator_count  = 1

# ── Cloud Run Serving ─────────────────────────────────────
serving_image           = "us-central1-docker.pkg.dev/your-gcp-project-id/recs-prod-images/tf-serving:2.16.1"
serving_grpc_port       = 8500
serving_rest_port       = 8501
cloud_run_min_instances = 2
cloud_run_max_instances = 20
cloud_run_cpu           = "4"
cloud_run_memory        = "8Gi"

# ── Storage ───────────────────────────────────────────────
gcs_bucket_location = "US"

# ── Monitoring ────────────────────────────────────────────
grafana_admin_password = "REPLACE_WITH_SECRET_MANAGER_REF"
