.PHONY: init fmt validate plan-local apply-local destroy-local plan-prod apply-prod logs-training logs-serving ps clean help

# Bypass malformed ~/.netrc that blocks provider downloads
export NETRC=/dev/null

TF      = terraform
ENVS    = envs
LOCAL   = $(ENVS)/local.tfvars
PROD    = $(ENVS)/prod.tfvars

# ──────────────────────────────────────────────────────────────
# Init
# ──────────────────────────────────────────────────────────────
init:
	$(TF) init -upgrade

# ──────────────────────────────────────────────────────────────
# Code quality
# ──────────────────────────────────────────────────────────────
fmt:
	$(TF) fmt -recursive

validate: init
	$(TF) validate

# ──────────────────────────────────────────────────────────────
# LOCAL environment (Docker)
# ──────────────────────────────────────────────────────────────
plan-local: init
	$(TF) plan -var-file=$(LOCAL) -out=tfplan-local

apply-local: init
	$(TF) apply -var-file=$(LOCAL) -auto-approve
	@echo ""
	@echo "╔══════════════════════════════════════════════════╗"
	@echo "║  Local Recs Pipeline is UP                       ║"
	@echo "╟──────────────────────────────────────────────────╢"
	@$(TF) output -var-file=$(LOCAL) | grep -E "url|endpoint|connection"
	@echo "╚══════════════════════════════════════════════════╝"

destroy-local:
	$(TF) destroy -var-file=$(LOCAL) -auto-approve

# ──────────────────────────────────────────────────────────────
# PROD environment (GCP) — requires authenticated gcloud
# ──────────────────────────────────────────────────────────────
plan-prod: init
	$(TF) plan -var-file=$(PROD) -out=tfplan-prod

apply-prod: init
	$(TF) apply -var-file=$(PROD) -auto-approve

destroy-prod:
	@echo "⚠️  This will destroy PRODUCTION resources. Press Ctrl-C to abort."
	@sleep 5
	$(TF) destroy -var-file=$(PROD)

# ──────────────────────────────────────────────────────────────
# Docker helpers (local only)
# ──────────────────────────────────────────────────────────────
ps:
	@docker ps --filter "label=project=recs" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-training:
	docker logs -f recs-local-training

logs-serving:
	docker logs -f recs-local-serving

shell-redis:
	docker exec -it recs-local-feature-store redis-cli

# Run a quick inference against local serving
test-inference:
	@echo "Sending test request to local TF Serving …"
	curl -s -X POST http://localhost:8501/v1/models/recs:predict \
	  -H "Content-Type: application/json" \
	  -d '{"instances": [{"user_id": "user_1"}]}' | python3 -m json.tool

# ──────────────────────────────────────────────────────────────
# Clean
# ──────────────────────────────────────────────────────────────
clean:
	rm -f tfplan-local tfplan-prod
	rm -rf .terraform.lock.hcl

# ──────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "recs-ops-terraform — Recommendation System Infrastructure"
	@echo ""
	@echo "  make init            Initialise Terraform providers"
	@echo "  make fmt             Auto-format all .tf files"
	@echo "  make validate        Validate configuration"
	@echo ""
	@echo "  make plan-local      Dry-run for local Docker environment"
	@echo "  make apply-local     Bring up local Docker environment"
	@echo "  make destroy-local   Tear down local Docker environment"
	@echo ""
	@echo "  make plan-prod       Dry-run for GCP production"
	@echo "  make apply-prod      Deploy to GCP production"
	@echo ""
	@echo "  make ps              List running recs containers"
	@echo "  make logs-training   Tail training container logs"
	@echo "  make logs-serving    Tail serving container logs"
	@echo "  make test-inference  POST a test recommendation request"
	@echo ""
