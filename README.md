# recs-ops-terraform

Terraform infrastructure for a **recommendation model training and serving pipeline**.

| Environment | Backend | When to use |
|-------------|---------|-------------|
| `local`     | Docker (containers on your laptop) | Development, demos, CI smoke tests |
| `prod`      | GCP (Vertex AI · Cloud Run · Memorystore · GCS) | Production |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        recs-ops-terraform                           │
│                                                                     │
│  ┌──────────────┐   features    ┌───────────────────────────────┐  │
│  │              │ ◄──────────── │      Feature Store            │  │
│  │   Training   │               │  local: Redis container       │  │
│  │   Pipeline   │               │  prod:  Cloud Memorystore     │  │
│  │              │               └───────────────────────────────┘  │
│  │  local: TF   │                                                   │
│  │  container   │  SavedModel   ┌───────────────────────────────┐  │
│  │  prod: Vertex│ ────────────► │      Model Registry           │  │
│  │  AI Pipeline │               │  local: /tmp/recs-model-…     │  │
│  └──────────────┘               │  prod:  GCS bucket            │  │
│                                 └──────────────┬────────────────┘  │
│                                                │ model path        │
│  ┌──────────────────────────────────────────── ▼ ────────────────┐ │
│  │                     Model Serving                             │ │
│  │   local: TF Serving container  (REST :8501 · gRPC :8500)      │ │
│  │   prod:  Cloud Run service     (auto-scaled)                  │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                       Monitoring                              │ │
│  │   local: Prometheus :9090  +  Grafana :3000                   │ │
│  │   prod:  Cloud Monitoring dashboards + uptime checks          │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Local demo
| Tool | Minimum version |
|------|----------------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.6 |
| [Docker Desktop](https://docs.docker.com/desktop/) | 4.x |

### GCP production (additional)
| Tool | Notes |
|------|-------|
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | authenticated via `gcloud auth application-default login` |
| GCP project | with Vertex AI, Cloud Run, Artifact Registry, Memorystore, and GCS APIs enabled |

---

## Quick start — local demo

```bash
# 1. Clone & init
git clone https://github.com/your-org/recs-ops-terraform
cd recs-ops-terraform
make init

# 2. Preview what Terraform will create
make plan-local

# 3. Spin up all containers
make apply-local

# 4. Open the dashboards
open http://localhost:3000   # Grafana  (admin / recs-local-admin)
open http://localhost:9090   # Prometheus
open http://localhost:6006   # TensorBoard

# 5. Watch training logs
make logs-training

# 6. Test a recommendation request (once training is done)
make test-inference

# 7. Tear down
make destroy-local
```

### What gets created locally

```
Docker containers                         Ports
────────────────────────────────────────────────
recs-local-feature-store  (Redis)        :6379
recs-local-training       (TF + TensorBoard) :6006
recs-local-serving        (TF Serving)   :8500 (gRPC)  :8501 (REST)
recs-local-prometheus     (Prometheus)   :9090
recs-local-grafana        (Grafana)      :3000
```

---

## GCP production deployment

```bash
# 1. Authenticate
gcloud auth application-default login

# 2. Set your project ID in envs/prod.tfvars
#    gcp_project_id = "your-gcp-project-id"

# 3. Preview
make plan-prod

# 4. Deploy
make apply-prod
```

### GCP resources created

| Resource | Purpose |
|----------|---------|
| `google_storage_bucket` | Model artifact store (versioned) |
| `google_artifact_registry_repository` | Docker image registry |
| `google_redis_instance` (Memorystore) | Feature store |
| `google_vertex_ai_dataset` | User-event dataset |
| `google_vertex_ai_pipeline_job` | Managed training pipeline |
| `google_cloud_run_v2_service` | Auto-scaled serving |
| `google_service_account` + IAM | Least-privilege SA for serving |
| `google_monitoring_dashboard` | Serving metrics dashboard |
| `google_monitoring_uptime_check_config` | Serving health check |

---

## Repository layout

```
recs-ops-terraform/
├── main.tf                    Root module — wires sub-modules together
├── variables.tf               All input variables
├── locals.tf                  Computed locals (naming, env booleans)
├── outputs.tf                 Root outputs (URLs, endpoints)
├── versions.tf                Provider version constraints
│
├── modules/
│   ├── feature_store/         Redis (local) / Memorystore (prod)
│   ├── model_registry/        Local dir / GCS + Artifact Registry
│   ├── training_pipeline/     TF container (local) / Vertex AI (prod)
│   ├── model_serving/         TF Serving (local) / Cloud Run (prod)
│   └── monitoring/            Prometheus+Grafana (local) / Cloud Monitoring
│
├── configs/
│   ├── training/
│   │   └── train.py           Two-tower TFRS training script
│   ├── serving/
│   │   ├── models.config      TF Serving model config
│   │   ├── batching.config    Request batching params
│   │   └── monitoring.config  Prometheus scrape config for TF Serving
│   └── monitoring/
│       └── grafana/
│           ├── datasources/   Grafana Prometheus datasource
│           └── dashboards/    Pre-built recs overview dashboard
│
└── envs/
    ├── local.tfvars           Local demo variables
    └── prod.tfvars            GCP production variables (fill in project ID)
```

---

## Useful Makefile targets

```
make init            Initialise Terraform providers
make fmt             Auto-format all .tf files
make validate        Validate configuration

make plan-local      Dry-run for local Docker environment
make apply-local     Bring up local Docker environment
make destroy-local   Tear down local Docker environment

make plan-prod       Dry-run for GCP production
make apply-prod      Deploy to GCP production

make ps              List running recs containers
make logs-training   Tail training container logs
make logs-serving    Tail serving container logs
make test-inference  POST a test recommendation request
```

---

## Model serving API

Once the serving container is running locally you can query it via REST:

```bash
# Check model status
curl http://localhost:8501/v1/models/recs

# Get top-N recommendations for a user
curl -X POST http://localhost:8501/v1/models/recs:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [{"user_id": "user_42"}]}'
```

---

## Extending to production

1. Push your training image to the Artifact Registry repo output by `module.model_registry`.  
2. Update `serving_image` in `envs/prod.tfvars` to point to the pushed image.  
3. Run `make apply-prod` — Cloud Run will roll to the new version with zero downtime.
