.PHONY: port-forward help

# Default target
help:
	@echo "Available targets:"
	@echo "  port-forward  - Start port forwarding for all services"
	@echo "  help         - Show this help message"

# Port forward target
port-forward:
	@echo "Starting port forwarding for all services..."
	@./scripts/port-forward.sh
