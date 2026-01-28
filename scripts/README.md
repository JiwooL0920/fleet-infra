# Scripts Directory

Automation scripts for local development and operations.

## Purpose

Contains shell scripts for common development tasks, service management, and health verification.

## Scripts

### Active Scripts

- **`port-forward.sh`** - Start port forwarding for all services
- **`verify-startup.sh`** - Verify service startup order and health
- **`fix-control-plane-ip.sh`** - Fix control plane IP after Colima restart
- **`test-crossplane.sh`** - Comprehensive Crossplane installation test suite
- **`validate-config-simple.sh`** - Configuration validation script

### Usage

Use these scripts with the Makefile targets for streamlined local development:

```bash
# Port forwarding for local development
make port-forward

# Verify service health
make verify-startup

# Fix IP after Colima restart
make fix-control-plane
```

## Secret Management

**Secrets are now automatically initialized by LocalStack** via startup hooks defined in the LocalStack HelmRelease. Manual secret initialization scripts have been removed as they are no longer needed.

To verify secrets were created:
```bash
kubectl port-forward -n localstack svc/localstack 4566:4566
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets --region us-east-1
```