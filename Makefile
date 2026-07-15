.PHONY: port-forward verify-startup init-aws-secrets fix-control-plane post-colima-restart setup-dns setup-github-secret get-ui-credentials refresh-credentials help precommit-install precommit-run precommit-update precommit-clean serve-ollama pull-ollama setup-ollama bootstrap-cilium docs-draft blog-draft update-docs docs-setup catalog validate-insights docs-render docs-validate docs-gen insight-draft insight-accept insight-draft-all insight-draft-ops cluster-health restart-test

# Ollama model to use - override with: make pull-ollama OLLAMA_MODEL=llama3.2
OLLAMA_MODEL ?= qwen2.5:72b

# Default target
help:
	@echo "Available targets:"
	@echo ""
	@echo "Local Development:"
	@echo "  bootstrap-cilium     - Bootstrap Cilium CNI (run BEFORE flux bootstrap after cluster recreation)"
	@echo "  setup-dns            - Setup local DNS entries for Traefik ingress (recommended)"
	@echo "  setup-github-secret  - Push GitHub PAT from env into LocalStack (needed for gitops-agent)"
	@echo "  refresh-credentials  - Force-sync ExternalSecrets and restart secret-consuming pods"
	@echo "  port-forward         - Start port forwarding for all services (alternative to DNS)"
	@echo "  verify-startup       - Verify service startup order and health"
	@echo "  fix-control-plane    - Fix control plane IP after Colima restart"
	@echo "  post-colima-restart  - Full recovery after Colima/Mac restart (single command)"
	@echo "  cluster-health       - Show Flux kustomization/HelmRelease health (read-only)"
	@echo "  restart-test         - Full colima stop → start → wait for Flux recovery (destructive)"
	@echo "  get-ui-credentials   - Show login credentials for all UI services"
	@echo ""
	@echo "Ollama (Local LLM for kagent):"
	@echo "  serve-ollama         - Start native Ollama bound to all interfaces (required for kagent in dev)"
	@echo "  setup-ollama         - Pull ALL models required by kagent (qwen2.5:72b, qwen2.5:14b-kagent, qwen2.5:3b)"
	@echo "  pull-ollama          - Pull OLLAMA_MODEL into native Ollama (default: $(OLLAMA_MODEL))"
	@echo "                         Override: make pull-ollama OLLAMA_MODEL=llama3.2"
	@echo ""
	@echo "Documentation & Blog:"
	@echo "  docs-setup           - Install Python docgen venv (one-time setup)"
	@echo "  catalog              - Extract service-catalog.json from manifests + env files"
	@echo "  validate-insights    - Validate service-insights/*.yaml schema"
	@echo "  docs-render          - Render all pages to docs-output/"
	@echo "  docs-validate        - Validate rendered pages (headings, tables, ADR refs)"
	@echo "  docs-gen             - Full local pipeline: catalog → render → validate"
	@echo "  insight-draft SVC=X  - AI-draft prose fields for service-insights/<X>.yaml"
	@echo "  insight-accept SVC=X - Validate and promote service-insights/<X>.suggested.yaml"
	@echo "  insight-draft-all    - AI-draft all stubs that still have TODO placeholders"
	@echo "  insight-draft-ops    - AI-draft operations runbooks for all services (review carefully)"
	@echo "  docs-draft           - AI-draft README/ADR/CLAUDE updates for staged infra changes"
	@echo "  update-docs          - Sync docs to jiwool0920.github.io and open a PR (incremental)"
	@echo "  update-docs MODE=all - Full reconcile: regenerate all component pages + rollups"
	@echo "  blog-draft           - Draft changelog-style blog post + open PR (local opencode + gh)"
	@echo "                         Optional: make blog-draft RANGE=HEAD~3..HEAD"
	@echo ""
	@echo "Pre-commit Hooks:"
	@echo "  precommit-install    - Install pre-commit hooks and required tools"
	@echo "  precommit-run        - Run pre-commit hooks on all files"
	@echo "  precommit-run-staged - Run pre-commit hooks on staged files only"
	@echo "  precommit-update     - Update pre-commit hooks to latest versions"
	@echo "  precommit-clean      - Clean pre-commit cache and reinstall"
	@echo ""
	@echo "Validation:"
	@echo "  validate-manifests   - Validate Kubernetes/Flux manifests"
	@echo "  validate-flux        - Check Flux API versions"
	@echo "  validate-kustomize   - Validate Kustomize overlays"
	@echo "  validate-all         - Run all validation checks"
	@echo ""
	@echo "  help                 - Show this help message"
	@echo ""
	@echo "NOTE: Secrets are automatically initialized via LocalStack startup hooks."
	@echo "      No manual secret initialization is required."
	@echo "      Exception: run 'make setup-github-secret' once to push your GitHub PAT."

# Setup local DNS for Traefik ingress
setup-dns:
	@echo "Setting up local DNS entries for Traefik ingress..."
	@./scripts/setup-local-dns.sh

# Bootstrap Cilium CNI (run BEFORE flux bootstrap after cluster recreation)
bootstrap-cilium: ## Bootstrap Cilium CNI (run BEFORE flux bootstrap after cluster recreation)
	@./scripts/bootstrap-cilium.sh

# Push GitHub PAT from environment into LocalStack (needed for gitops-agent)
# Reads GITHUB_TOKEN or GITHUB_PAT from env, or prompts interactively.
# Creates the github-pat-bootstrap K8s Secret in the localstack namespace.
# LocalStack reads this on startup and creates github/mcp/token in its Secrets Manager.
# Run once per fresh cluster. LocalStack persistence means no re-run on pod restart.
setup-github-secret:
	@echo "Creating github-pat-bootstrap Secret for LocalStack..."
	@./scripts/init-github-secret.sh

# Register dev-applications spoke with Argo CD on the hub.
# NOTE: this target was removed by ADR-018. The Argo CD Cluster Secret for the spoke is
# now provisioned by Terraform (terraform-infra) directly on the hub via
# kubernetes_secret_v1. No fleet-infra manifest or Makefile step is needed.
# See docs/adr/018-terraform-provisioned-argocd-cluster-secret.md.

# Port forward target
port-forward:
	@echo "Starting port forwarding for all services..."
	@./scripts/port-forward.sh

# Verify startup target
verify-startup:
	@echo "Verifying service startup order and health..."
	@./scripts/verify-startup.sh

# Initialize AWS secrets target (Deprecated - secrets are now auto-initialized)
# Secrets are auto-created when LocalStack starts via enableStartupScripts.
# This target is kept for backward compatibility but does nothing.
init-aws-secrets:
	@echo "⚠️  This target is deprecated."
	@echo "Secrets are now automatically initialized by LocalStack startup hooks."
	@echo "No manual initialization is needed."
	@echo ""
	@echo "To verify secrets were created:"
	@echo "  kubectl port-forward -n localstack svc/localstack 4566:4566"
	@echo "  aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets --region us-east-1"

# Fix control plane IP after Colima restart
fix-control-plane:
	@echo "Fixing control plane IP configuration after Colima restart..."
	@./scripts/fix-control-plane-ip.sh

# Complete post-restart setup (recommended after Colima restart)
# Handles: IP fix, credential sync, failed job cleanup, Flux reconciliation, Ollama check
post-colima-restart:
	@./scripts/post-colima-restart.sh

# Show Flux kustomization and HelmRelease health (read-only, safe to run anytime)
cluster-health:
	@./scripts/test-restart-recovery.sh

# Full colima stop → start → wait for Flux to self-heal. Destructive — prompts before stopping.
restart-test:
	@./scripts/test-restart-recovery.sh --yes

get-ui-credentials:
	@./scripts/get-ui-credentials.sh

# Force-sync all ExternalSecrets from LocalStack, restart pods, and verify credentials
refresh-credentials:
	@./scripts/refresh-credentials.sh

# Start native Ollama bound to all interfaces so Kind cluster pods can reach it via host.docker.internal
serve-ollama:
	@echo "Starting Ollama (bound to 0.0.0.0 for cluster access via host.docker.internal)..."
	@lsof -ti :11434 | xargs kill -9 2>/dev/null || true
	@OLLAMA_HOST=0.0.0.0 ollama serve

# Pull the configured LLM model into native Ollama
pull-ollama:
	@echo "Pulling $(OLLAMA_MODEL) model into Ollama..."
	@ollama pull $(OLLAMA_MODEL)
	@echo "Done. Run 'make serve-ollama' to start serving."

# Pull ALL models required by kagent agents:
#   qwen2.5:72b          → default-model-config  (coordinator-agent, k8s-agent, gitops-agent)
#   qwen2.5:14b-kagent   → fast-model-config      (observability, flux, helm, security, finops agents)
#   qwen2.5:3b           → classifier-model-config (classifier-agent — input safety gate)
# Skips models that already exist locally (e.g. custom Modelfile builds like qwen2.5:14b-kagent).
setup-ollama:
	@echo "Pulling all kagent-required Ollama models..."
	@echo ""
	@echo "[1/3] qwen2.5:72b (default-model-config — coordinator, k8s, gitops agents)..."
	@if ollama list | grep -q "^qwen2.5:72b "; then \
		echo "  already present — skipping pull."; \
	else \
		ollama pull qwen2.5:72b; \
	fi
	@echo ""
	@echo "[2/3] qwen2.5:14b-kagent (fast-model-config — observability, flux, helm, security, finops agents)..."
	@if ollama list | grep -q "^qwen2.5:14b-kagent "; then \
		echo "  already present — skipping pull."; \
	else \
		ollama pull qwen2.5:14b-kagent; \
	fi
	@echo ""
	@echo "[3/3] qwen2.5:3b (classifier-model-config — input safety gate)..."
	@if ollama list | grep -q "^qwen2.5:3b "; then \
		echo "  already present — skipping pull."; \
	else \
		ollama pull qwen2.5:3b; \
	fi
	@echo ""
	@echo "All kagent models ready. Run 'make serve-ollama' to start serving."

# ==============================================================================
# Deterministic Documentation Generation
# ==============================================================================

# Install Python docgen deps into the venv (one-time per machine)
docs-setup:
	@echo "Setting up docs venv..."
	@python3 -m venv scripts/docgen/.venv
	@scripts/docgen/.venv/bin/pip install -q -r scripts/docgen/requirements.txt
	@echo "✓ docs venv ready at scripts/docgen/.venv/"

# Extract service-catalog.json from manifests + env files.
# Re-run whenever you add/remove services or change chart versions.
catalog:
	@scripts/docgen/.venv/bin/python3 scripts/docgen/catalog.py

# Validate all service-insights/*.yaml files against the schema.
validate-insights:
	@scripts/docgen/.venv/bin/python3 scripts/docgen/insight_schema.py

# Render all component + rollup pages from catalog + insights into docs-output/.
docs-render:
	@scripts/docgen/.venv/bin/python3 scripts/docgen/render.py --output-dir docs-output

# Validate rendered markdown pages (headings, empty tables, ADR refs, mermaid balance).
docs-validate:
	@scripts/docgen/.venv/bin/python3 scripts/docgen/validate.py --docs-dir docs-output

# Generate prose fields (intro, purpose, features, architecture_diagrams) for a service insight
# YAML using opencode. The LLM reasons from manifests + catalog entry + ADRs.
# Config values (CPU, memory, replicas, chart version) always come from service-catalog.json.
#
# Usage:
#   make insight-draft SVC=traefik                        # initial draft (skips filled fields)
#   make insight-draft SVC="traefik loki"                 # batch
#   make insight-draft SVC=loki FORCE=1                   # overwrite all fields (post-refactor)
#   make insight-draft SVC=loki FIELDS=architecture_diagrams  # re-draft one field only
#   make insight-draft-all                                # all stubs with TODO placeholders
#
# FORCE=1   — overwrite even already-filled fields (use after an architecture refactor)
# FIELDS=   — comma-separated field names to re-draft (e.g. FIELDS=architecture_diagrams,purpose)
FORCE ?=
FIELDS ?=
insight-draft:
	@if [ -z "$(SVC)" ]; then echo "Usage: make insight-draft SVC=<slug> [FORCE=1] [FIELDS=field1,field2]"; exit 1; fi
	@scripts/docgen/.venv/bin/python3 scripts/docgen/insight_draft.py $(SVC) \
		$(if $(FORCE),--force,) \
		$(if $(FIELDS),--fields $(FIELDS),)
	@echo ""
	@for svc in $(SVC); do echo "  suggestion → $$(pwd)/service-insights/$$svc.suggested.yaml"; done

insight-accept:
	@if [ -z "$(SVC)" ]; then echo "Usage: make insight-accept SVC=<slug>"; exit 1; fi
	@for svc in $(SVC); do \
		suggested="service-insights/$$svc.suggested.yaml"; \
		primary="service-insights/$$svc.yaml"; \
		if [ ! -f "$$suggested" ]; then \
			echo "ERROR: $$suggested not found"; \
			exit 1; \
		fi; \
		scripts/docgen/.venv/bin/python3 scripts/docgen/insight_schema.py "$$suggested"; \
		mv "$$suggested" "$$primary"; \
		echo "  accepted → $$(pwd)/$$primary"; \
	done

# Draft insights for ALL enabled services that still have TODO placeholders.
insight-draft-all:
	@stubs=$$(scripts/docgen/.venv/bin/python3 -c "import json; from pathlib import Path; c=json.load(open('service-catalog.json'))['services']; print(' '.join(s for s,v in c.items() if v['enabled'] and Path(f'service-insights/{s}.yaml').exists() and '<!-- TODO:' in Path(f'service-insights/{s}.yaml').read_text()))"); \
	echo "Drafting: $$stubs"; \
	for svc in $$stubs; do \
		scripts/docgen/.venv/bin/python3 scripts/docgen/insight_draft.py $$svc; \
	done

# Draft operations runbooks (scenarios, symptoms, steps) for all services.
# REVIEW CAREFULLY: commands reference real resource names but scenarios are LLM-generated.
# Use FORCE=1 to overwrite existing operations sections.
insight-draft-ops:
	@all_svcs=$$(scripts/docgen/.venv/bin/python3 -c "import json; from pathlib import Path; c=json.load(open('service-catalog.json'))['services']; print(' '.join(s for s,v in c.items() if v['enabled'] and Path(f'service-insights/{s}.yaml').exists()))"); \
	echo "Drafting operations for: $$all_svcs"; \
	for svc in $$all_svcs; do \
		scripts/docgen/.venv/bin/python3 scripts/docgen/insight_draft.py $$svc --fields operations $(if $(FORCE),--force,); \
	done

# Full local generate + validate pipeline (catalog → render → validate).
# Outputs go to docs-output/ for inspection before running update-docs.
docs-gen: catalog validate-insights docs-render docs-validate
	@echo ""
	@echo "✓ Docs generated in docs-output/"
	@echo "  Component pages: $$(pwd)/docs-output/components/"
	@echo "  Run 'make update-docs' to sync to the blog repo and open a PR."


# Draft README/ADR/CLAUDE updates for changed infra services.
# Run this when the docs-freshness pre-push hook blocks you.
docs-draft:
	@echo "Preparing git diff for opencode..."
	@DIFF=$$(git diff HEAD 2>/dev/null); \
	STAGED=$$(git diff --cached 2>/dev/null); \
	CONTEXT="$${STAGED:-$$DIFF}"; \
	if [ -z "$$CONTEXT" ]; then \
		echo "No staged or unstaged changes found. Stage or commit your changes first."; \
		exit 1; \
	fi; \
	TMPFILE=$$(mktemp /tmp/docs-draft-XXXX.txt); \
	printf "Review this git diff from the flux-infra GitOps repository.\n\nIdentify which services changed (paths under apps/base/ and base/services/).\nFor each changed service, propose concise updates for:\n- README.md (service list / dependency layer)\n- CLAUDE.md (if architecture changed)\n- A new or updated docs/adr/ entry if this is a significant decision\n\nOutput proposed changes as markdown diffs or file sections.\nDo NOT apply them — the human will review.\n\n---\n%s\n" "$$CONTEXT" > "$$TMPFILE"; \
	opencode run "Review the diff in the attached file and propose documentation updates." \
		-f "$$TMPFILE" \
		--dangerously-skip-permissions \
		< /dev/null; \
	rm -f "$$TMPFILE"
	@echo ""
	@echo "Review the suggestions above and apply manually or with Cursor/opencode."

# Draft a blog post and open a PR in jiwool0920.github.io (full automation).
# Uses your local opencode config and gh authentication — no secrets needed.
# Optional: override the git range with RANGE=HEAD~3..HEAD
blog-draft:
	@./scripts/blog-draft.sh $(RANGE)

# Sync docs/projects/flux-infra in jiwool0920.github.io with the current state of
# flux-infra services. Reads a watermark from the blog repo to determine what changed.
# Opens a PR in jiwool0920.github.io for review before merging.
#
# Incremental (default): only services changed since last sync
#   make update-docs
#
# Full reconcile: all enabled services + regenerate all index/architecture/nav pages
#   make update-docs MODE=all
update-docs:
	@./scripts/update-docs.sh $(MODE)

# ==============================================================================
# Pre-commit Hooks
# ==============================================================================

# Check if pre-commit is installed
check-precommit:
	@command -v pre-commit >/dev/null 2>&1 || \
		(echo "❌ pre-commit is not installed" && \
		 echo "Install with: brew install pre-commit" && \
		 echo "or: pip install pre-commit" && \
		 exit 1)

# Check if required validation tools are installed
check-validation-tools:
	@echo "Checking validation tools..."
	@command -v kubeconform >/dev/null 2>&1 || echo "⚠️  kubeconform not installed (brew install kubeconform)"
	@command -v kustomize >/dev/null 2>&1 || echo "⚠️  kustomize not installed (brew install kustomize)"
	@command -v yq >/dev/null 2>&1 || echo "⚠️  yq not installed (brew install yq)"
	@command -v yamllint >/dev/null 2>&1 || echo "⚠️  yamllint not installed (brew install yamllint)"
	@command -v shellcheck >/dev/null 2>&1 || echo "⚠️  shellcheck not installed (brew install shellcheck)"
	@command -v markdownlint >/dev/null 2>&1 || echo "⚠️  markdownlint not installed (brew install markdownlint-cli)"
	@command -v detect-secrets >/dev/null 2>&1 || echo "⚠️  detect-secrets not installed (brew install detect-secrets)"
	@echo "✓ Tool check complete"

# Install pre-commit hooks and required tools
precommit-install: check-precommit
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@pre-commit install --hook-type commit-msg
	@echo ""
	@echo "Creating secrets baseline..."
	@if command -v detect-secrets >/dev/null 2>&1; then \
		detect-secrets scan > .secrets.baseline 2>/dev/null || touch .secrets.baseline; \
	else \
		touch .secrets.baseline; \
		echo "⚠️  detect-secrets not installed, created empty baseline"; \
	fi
	@echo ""
	@echo "✓ Pre-commit hooks installed!"
	@echo ""
	@echo "Checking for validation tools..."
	@$(MAKE) check-validation-tools
	@echo ""
	@echo "To install all tools at once:"
	@echo "  brew install kubeconform kustomize yq yamllint shellcheck markdownlint-cli detect-secrets"

# Run pre-commit on all files
precommit-run: check-precommit
	@echo "Running pre-commit hooks on all files..."
	@pre-commit run --all-files

# Run pre-commit on staged files only
precommit-run-staged: check-precommit
	@echo "Running pre-commit hooks on staged files..."
	@pre-commit run

# Update pre-commit hooks to latest versions
precommit-update: check-precommit
	@echo "Updating pre-commit hooks..."
	@pre-commit autoupdate
	@echo "✓ Pre-commit hooks updated!"

# Clean pre-commit cache and reinstall
precommit-clean: check-precommit
	@echo "Cleaning pre-commit cache..."
	@pre-commit clean
	@pre-commit uninstall
	@echo "✓ Cache cleaned and hooks uninstalled"
	@echo ""
	@echo "To reinstall, run: make precommit-install"

# ==============================================================================
# Validation Commands
# ==============================================================================

# Validate Kubernetes/Flux manifests
validate-manifests:
	@echo "Validating Kubernetes/Flux manifests..."
	@./scripts/pre-commit/validate-manifests.sh

# Check Flux API versions
validate-flux:
	@echo "Checking Flux API versions..."
	@./scripts/pre-commit/check-flux-versions.sh

# Validate Kustomize overlays
validate-kustomize:
	@echo "Validating Kustomize overlays..."
	@./scripts/pre-commit/validate-kustomize.sh

# Run all validations
validate-all: validate-flux validate-kustomize validate-manifests
	@echo ""
	@echo "✓ All validations passed!"
