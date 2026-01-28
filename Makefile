.PHONY: port-forward verify-startup init-aws-secrets fix-control-plane post-colima-restart setup-dns help

# Default target
help:
	@echo "Available targets:"
	@echo "  setup-dns            - Setup local DNS entries for Traefik ingress (recommended)"
	@echo "  port-forward         - Start port forwarding for all services (alternative to DNS)"
	@echo "  verify-startup       - Verify service startup order and health"
	@echo "  fix-control-plane    - Fix control plane IP after Colima restart"
	@echo "  post-colima-restart  - Complete post-restart setup (fix IP only)"
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


