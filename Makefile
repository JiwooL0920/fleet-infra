.PHONY: port-forward verify-startup init-aws-secrets help

# Default target
help:
	@echo "Available targets:"
	@echo "  port-forward     - Start port forwarding for all services"
	@echo "  verify-startup   - Verify service startup order and health"
	@echo "  init-aws-secrets - Initialize AWS secrets in LocalStack"
	@echo "  help            - Show this help message"

# Port forward target
port-forward:
	@echo "Starting port forwarding for all services..."
	@./scripts/port-forward.sh

# Verify startup target
verify-startup:
	@echo "Verifying service startup order and health..."
	@./scripts/verify-startup.sh

# Initialize AWS secrets target
init-aws-secrets:
	@echo "Initializing AWS secrets in LocalStack..."
	@echo "Checking if LocalStack is accessible on port 4566..."
	@if ! curl -s http://localhost:4566/_localstack/health >/dev/null 2>&1; then \
		echo "Starting LocalStack port forwarding..."; \
		kubectl port-forward -n localstack svc/localstack 4566:4566 & \
		echo "Waiting for LocalStack to be accessible..."; \
		for i in {1..30}; do \
			if curl -s http://localhost:4566/_localstack/health >/dev/null 2>&1; then \
				echo "LocalStack is ready!"; \
				break; \
			fi; \
			sleep 2; \
		done; \
	else \
		echo "LocalStack is already accessible on port 4566"; \
	fi
	@./scripts/init-pgadmin-secrets.sh
	@./scripts/init-redis-secret.sh


