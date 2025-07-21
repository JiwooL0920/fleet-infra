.PHONY: port-forward verify-startup help

# Default target
help:
	@echo "Available targets:"
	@echo "  port-forward   - Start port forwarding for all services"
	@echo "  verify-startup - Verify service startup order and health"
	@echo "  help          - Show this help message"

# Port forward target
port-forward:
	@echo "Starting port forwarding for all services..."
	@./scripts/port-forward.sh

# Verify startup target
verify-startup:
	@echo "Verifying service startup order and health..."
	@./scripts/verify-startup.sh


