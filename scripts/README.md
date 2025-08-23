# Scripts Directory

Automation scripts for local development and operations.

## Purpose

Contains shell scripts for common development tasks, secret initialization, service management, and health verification.

## Scripts

- `init-pgadmin-secrets.sh` - Initialize pgAdmin4 secrets in LocalStack
- `init-redis-secret.sh` - Initialize Redis secrets in LocalStack  
- `port-forward.sh` - Start port forwarding for all services
- `verify-startup.sh` - Verify service startup order and health

Use these scripts with the Makefile targets for streamlined local development.