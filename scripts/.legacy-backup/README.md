# Legacy Backup

This directory contains legacy scripts and configurations that were replaced by automated systems during the Crossplane/GitOps modernization.

## Replaced Scripts

### Manual Secret Initialization Scripts
These scripts were replaced by automated Kubernetes Job (`apps/base/infrastructure/secret-init-job.yaml`) that runs in Wave 1:

- `init-grafana-secrets.sh` - Manual Grafana admin credentials setup
- `init-pgadmin-secrets.sh` - Manual pgAdmin4 credentials setup  
- `init-redis-secret.sh` - Manual Redis password setup
- `init-traefik-secrets.sh` - Manual Traefik dashboard credentials setup
- `init-crossplane-secrets.sh` - Manual Crossplane AWS credentials setup

## Current Automated System

### Secret Management Flow
1. **Wave 1**: Kubernetes Job automatically creates all secrets in LocalStack
2. **Wave 2**: External Secrets Operator syncs secrets to Kubernetes
3. **Wave 3+**: Services consume secrets via ExternalSecret resources

### Benefits of New System
- **GitOps Native**: Secrets managed through Kubernetes resources
- **Automatic**: No manual intervention required after cluster restart
- **Dependency Aware**: Proper wave ordering ensures secrets exist before services start
- **Consistent**: Same credential generation logic every time
- **Auditable**: All operations tracked in Kubernetes events

## Recovery Usage

These legacy scripts can still be used for:
- Manual recovery if automation fails
- Understanding secret structure and requirements
- Emergency cluster setup scenarios
- Development and testing workflows

## Migration Notes

Replaced manual `make init-aws-secrets` workflow with:
```yaml
# apps/base/infrastructure/secret-init-job.yaml
# Automated Job that creates all required secrets
```

Services migrated from hardcoded credentials to ExternalSecret resources:
- Grafana: `apps/base/kube-prometheus-stack/externalsecret.yaml`
- pgAdmin4: `apps/base/pgadmin4/externalsecret.yaml`
- Redis: `apps/base/redis/externalsecret.yaml`
- Traefik: `apps/base/traefik/externalsecret.yaml`
- N8N: `apps/base/n8n/externalsecret.yaml`
- Temporal: `apps/base/temporal/externalsecret.yaml`

Date: 2025-08-22
Migration: Manual → Automated Secret Management with Crossplane + External Secrets