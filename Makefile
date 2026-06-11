.PHONY: port-forward verify-startup init-aws-secrets fix-control-plane post-colima-restart setup-dns setup-github-secret setup-grafana-db get-ui-credentials refresh-credentials help precommit-install precommit-run precommit-update precommit-clean serve-ollama pull-ollama setup-ollama bootstrap-cilium docs-draft docs-draft-blog blog-draft

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
	@echo "  setup-grafana-db     - Store PG password in LocalStack for Grafana PostgreSQL backend"
	@echo "  port-forward         - Start port forwarding for all services (alternative to DNS)"
	@echo "  verify-startup       - Verify service startup order and health"
	@echo "  fix-control-plane    - Fix control plane IP after Colima restart"
	@echo "  post-colima-restart  - Full recovery after Colima/Mac restart (single command)"
	@echo "  get-ui-credentials   - Show login credentials for all UI services"
	@echo "  refresh-credentials  - Force-sync secrets from LocalStack and restart pods"
	@echo ""
	@echo "Ollama (Local LLM for kagent):"
	@echo "  serve-ollama         - Start native Ollama bound to all interfaces (required for kagent in dev)"
	@echo "  setup-ollama         - Pull ALL models required by kagent (qwen2.5:72b, qwen2.5:14b-kagent, qwen2.5:3b)"
	@echo "  pull-ollama          - Pull OLLAMA_MODEL into native Ollama (default: $(OLLAMA_MODEL))"
	@echo "                         Override: make pull-ollama OLLAMA_MODEL=llama3.2"
	@echo ""
	@echo "Documentation & Blog:"
	@echo "  docs-draft           - AI-draft README/ADR/CLAUDE updates for staged infra changes"
	@echo "  docs-draft-blog      - Preview AI-drafted blog post to stdout (no PR)"
	@echo "  blog-draft           - Draft blog post + open PR in jiwool0920.github.io"
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

# Store PG app password in LocalStack for Grafana's PostgreSQL backend.
# Run once per fresh cluster (or after PG cluster recreation).
setup-grafana-db:
	@echo "Storing PostgreSQL password in LocalStack for Grafana..."
	@./scripts/init-grafana-db-secret.sh

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
post-colima-restart: fix-control-plane refresh-credentials
	@echo ""
	@echo "🧹 Cleaning up failed jobs from restart window..."
	@kubectl delete job create-grafana-sa-token -n monitoring --ignore-not-found=true 2>/dev/null; true
	@echo ""
	@echo "⏳ Waiting for Grafana to be healthy..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=120s 2>/dev/null || \
		echo "⚠️  Grafana not ready yet — grafana-sa-setup may need manual reconcile later"
	@echo ""
	@echo "🔄 Reconciling grafana-sa-setup (creates SA token for kagent)..."
	@flux reconcile kustomization grafana-sa-setup --timeout=3m 2>/dev/null || \
		echo "⚠️  grafana-sa-setup reconcile timed out — retry with: flux reconcile kustomization grafana-sa-setup"
	@echo ""
	@if [[ -n "$$GITHUB_TOKEN" || -n "$$GITHUB_PAT" ]]; then \
		echo "🔑 Detected GitHub token in environment. Re-syncing GitHub secret..."; \
		./scripts/init-github-secret.sh; \
	else \
		echo "💡 Tip: Run 'make setup-github-secret' if you use the gitops-agent (requires GitHub PAT)."; \
	fi
	@echo ""
	@echo "🦙 Checking native Ollama (needed for kagent)..."
	@if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then \
		echo "  ✅ Ollama is running"; \
	else \
		echo "  ⚠️  Ollama is not running. Start with: make serve-ollama"; \
	fi
	@echo ""
	@echo "📊 Final kustomization health:"
	@flux get kustomizations 2>/dev/null | grep -E "False|Unknown" | grep -v "ollama" || echo "  ✅ All kustomizations healthy (ollama intentionally suspended)"
	@echo ""
	@echo "✅ Post-Colima restart setup completed!"
	@echo "   Run 'make get-ui-credentials' for login credentials."

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
# Documentation Assist (AI-drafted, human-reviewed)
# ==============================================================================

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
	printf "Review this git diff from the fleet-infra GitOps repository.\n\nIdentify which services changed (paths under apps/base/ and base/services/).\nFor each changed service, propose concise updates for:\n- README.md (service list / dependency layer)\n- CLAUDE.md (if architecture changed)\n- A new or updated docs/adr/ entry if this is a significant decision\n\nOutput proposed changes as markdown diffs or file sections.\nDo NOT apply them — the human will review.\n\n---\n%s\n" "$$CONTEXT" > "$$TMPFILE"; \
	opencode run "Review the diff in the attached file and propose documentation updates." \
		-f "$$TMPFILE" \
		--dangerously-skip-permissions \
		< /dev/null; \
	rm -f "$$TMPFILE"
	@echo ""
	@echo "Review the suggestions above and apply manually or with Cursor/opencode."

# Preview a blog post draft to stdout (no PR).
# Useful for checking output before committing via 'make blog-draft'.
docs-draft-blog:
	@echo "Drafting blog post preview from recent commits..."
	@TMPFILE=$$(mktemp /tmp/blog-prompt-XXXX.txt); \
	TODAY=$$(date '+%Y-%m-%d'); \
	LOG=$$(git log -1 --format="commit %H%nauthor: %an%ndate: %ai%nsubject: %s%n%nbody:%n%b" 2>/dev/null); \
	PATCH=$$(git diff HEAD~1 HEAD -- 'apps/base/' 'base/services/' 'docs/adr/' 2>/dev/null | head -c 8192); \
	printf "Write a MkDocs Material blog post for https://jiwool0920.github.io authored by Jiwoo Lee.\n\nCommit context:\n%s\n\nGit diff:\n%s\n\n---\nFrontmatter format:\n---\ndate: %s\ncategories:\n  - Infrastructure\n  - <Component>\ntags:\n  - <tags>\nauthors:\n  - jiwoo\n---\n\nRequirements:\n- 2-3 sentence intro then <!-- more --> fold\n- Mermaid diagrams where useful\n- Sections: Overview, Why This Change, Technical Details, Operational Impact\n- Tone: direct and practical\n- Output ONLY the markdown body\n" "$$LOG" "$$PATCH" "$$TODAY" > "$$TMPFILE"; \
	opencode run "Write the blog post described in the attached file." \
		-f "$$TMPFILE" \
		--dangerously-skip-permissions \
		< /dev/null; \
	rm -f "$$TMPFILE"
	@echo ""
	@echo "Happy with the output? Run 'make blog-draft' to branch the blog repo and open a PR."

# Draft a blog post and open a PR in jiwool0920.github.io (full automation).
# Uses your local opencode config and gh authentication — no secrets needed.
# Optional: override the git range with RANGE=HEAD~3..HEAD
blog-draft:
	@./scripts/blog-draft.sh $(RANGE)

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
