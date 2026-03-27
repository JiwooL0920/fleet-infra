.PHONY: port-forward verify-startup init-aws-secrets fix-control-plane post-colima-restart setup-dns get-ui-credentials help precommit-install precommit-run precommit-update precommit-clean serve-ollama pull-ollama

# Default target
help:
	@echo "Available targets:"
	@echo ""
	@echo "Local Development:"
	@echo "  setup-dns            - Setup local DNS entries for Traefik ingress (recommended)"
	@echo "  port-forward         - Start port forwarding for all services (alternative to DNS)"
	@echo "  verify-startup       - Verify service startup order and health"
	@echo "  fix-control-plane    - Fix control plane IP after Colima restart"
	@echo "  post-colima-restart  - Complete post-restart setup (fix IP only)"
	@echo "  get-ui-credentials   - Show login credentials for all UI services"
	@echo ""
	@echo "Ollama (Local LLM for kagent):"
	@echo "  serve-ollama         - Start native Ollama bound to all interfaces (required for kagent in dev)"
	@echo "  pull-ollama          - Pull the llama3.2 model into native Ollama"
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

# Setup local DNS for Traefik ingress
setup-dns:
	@echo "Setting up local DNS entries for Traefik ingress..."
	@./scripts/setup-local-dns.sh

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
# Secrets are auto-initialized by LocalStack startup hooks - no manual init needed
post-colima-restart: fix-control-plane
	@echo "Post-Colima restart setup completed!"
	@echo "Secrets will be auto-initialized when LocalStack starts (via init hooks + persistence)."
	@echo "Run 'make verify-startup' to check service health."

get-ui-credentials:
	@./scripts/get-ui-credentials.sh

# Start native Ollama bound to all interfaces so Kind cluster pods can reach it via host.docker.internal
serve-ollama:
	@echo "Starting Ollama (bound to 0.0.0.0 for cluster access via host.docker.internal)..."
	@OLLAMA_HOST=0.0.0.0 ollama serve

# Pull the configured LLM model into native Ollama
pull-ollama:
	@echo "Pulling llama3.2 model into Ollama..."
	@ollama pull llama3.2
	@echo "Done. Run 'make serve-ollama' to start serving."

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
