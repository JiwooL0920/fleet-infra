# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes GitOps infrastructure repository using Flux CD for multi-environment deployment. It manages infrastructure applications across development and production environments with complete separation and automated deployments.

## Common Commands

### Environment Bootstrap
```bash
# Bootstrap development environment (tracks develop branch)
./scripts/flux-bootstrap.sh dev

# Bootstrap production environment (tracks main branch)
./scripts/flux-bootstrap.sh prod
```

### Port Forwarding
```bash
# Start port forwarding for all services
make port-forward
# OR
./scripts/port-forward.sh
```

### Flux Operations
```bash
# Check Flux status
flux get all

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Check sources and kustomizations
flux get sources git
flux get kustomizations
```

### Kubernetes Operations
```bash
# Check application health
kubectl get pods --all-namespaces
kubectl get helmrelease --all-namespaces

# Check PostgreSQL cluster
kubectl get cluster -n cnpg-system
kubectl describe cluster postgresql-cluster -n cnpg-system

# Get database credentials
kubectl get secret postgresql-cluster-app -n cnpg-system -o jsonpath='{.data.username}' | base64 -d
kubectl get secret postgresql-cluster-app -n cnpg-system -o jsonpath='{.data.password}' | base64 -d
```

### Testing and Validation
```bash
# Pre-commit checks
./scripts/pre-commit-check.sh

# Test Flux changes
./scripts/test-flux-changes.sh

# Verify service startup order and health
make verify-startup
# OR
./scripts/verify-startup.sh
```

## Architecture and Structure

### Multi-Environment GitOps Strategy
- **Development Environment**: Tracks `develop` branch, deploys to dev cluster
- **Production Environment**: Tracks `main` branch, deploys to prod cluster
- **Separation**: Complete environment isolation using different paths and branches

### Key Architectural Components

#### Flux CD Configuration
- Source controller manages Git repository synchronization
- Kustomize controller applies Kubernetes manifests
- Helm controller manages Helm releases
- Different sync intervals: dev (1m), prod (10m)

#### Application Stack
- **CloudNative PostgreSQL**: 3-node HA cluster with automated backups
- **N8N**: Workflow automation engine with PostgreSQL backend (depends on PostgreSQL)
- **Temporal**: Workflow orchestration platform (depends on PostgreSQL) 
- **Traefik**: Ingress controller and load balancer
- **Kube-Prometheus-Stack**: Monitoring with Grafana, Prometheus, Alertmanager
- **LocalStack**: Local AWS services emulation (required for PostgreSQL backups)
- **Weave GitOps**: GitOps dashboard and management

#### Service Dependencies (startup order)
1. **LocalStack** (foundational service)
2. **CloudNative PG Operator** 
3. **PostgreSQL Cluster** (depends on operator + LocalStack)
4. **N8N, Temporal** (depend on PostgreSQL)
5. **Other services** (Traefik, monitoring, etc.)

#### Database Architecture
- PostgreSQL 16 with CloudNative PG operator
- High availability with 3 instances
- Automated backups to LocalStack S3
- Pre-configured databases: `appdb`, `temporal`, `temporal_visibility`
- Auto-generated secure credentials stored in Kubernetes secrets

### Directory Structure Logic

```
apps/base/           # Base application configurations (Helm releases)
├── cnpg/           # PostgreSQL cluster and operator
├── n8n/            # Workflow automation
├── temporal/       # Workflow orchestration
├── traefik/        # Ingress controller
└── ...

base/               # Base Kustomization aggregating all apps
├── kustomization.yaml
├── environment.env # Base environment variables
└── services/       # Service-specific configurations

clusters/stages/    # Environment-specific configurations
├── dev/            # Development environment
│   └── clusters/services-amer/
│       ├── flux-system/     # Flux controllers (tracks develop branch)
│       └── kustomization.yaml
└── prod/           # Production environment (similar structure, tracks main branch)

scripts/            # Automation scripts
├── flux-bootstrap.sh    # Environment-aware bootstrap
├── port-forward.sh      # Service port forwarding
└── ...
```

### Branch and Environment Mapping
- `develop` branch → Dev environment → Path: `./clusters/stages/dev/clusters/services-amer`
- `main` branch → Prod environment → Path: `./clusters/stages/prod/clusters/services-amer`

### Port Mappings (when port forwarding is active)
- LocalStack: 4566
- N8N: 5678
- Grafana: 3030
- Prometheus: 9090
- Alertmanager: 9093
- Node Exporter: 9100
- Weave GitOps: 9001
- Temporal UI: 8090

## Key Development Workflows

### Making Infrastructure Changes
1. Create feature branch from `develop`
2. Make changes to application configurations
3. Test with `./scripts/test-flux-changes.sh`
4. Commit and push to feature branch
5. Create PR to `develop`
6. After merge, changes auto-deploy to dev environment
7. Validate in dev, then merge `develop` to `main` for production

### Adding New Applications
1. Create base configuration in `apps/base/<app-name>/`
2. Include namespace, kustomization, and helmrelease files
3. Add to base kustomization in `base/kustomization.yaml`
4. Test in development environment first

### Environment Configuration Differences
- Use cluster-vars-patch.yaml files for environment-specific overrides
- Base configurations in `apps/base/` should be environment-agnostic
- Environment-specific values in `clusters/stages/*/clusters/services-amer/`

## Security and Operations

### Database Security
- No hardcoded credentials in Git
- Auto-generated passwords stored in Kubernetes secrets
- PostgreSQL cluster uses secure configurations with resource limits

### GitOps Security
- SSH key authentication for Git repository access
- RBAC policies for Flux controllers
- Network policies and pod security standards

### Backup Strategy
- Automated PostgreSQL backups to LocalStack S3
- Daily backup schedule at 2:00 AM UTC
- 30-day retention policy

## Important Notes

- Never commit database credentials or secrets to Git
- Always test changes in development environment first
- Use the bootstrap script for setting up new environments
- Monitor Flux reconciliation status when making changes
- PostgreSQL databases are created automatically via post-init SQL
- All applications use PostgreSQL from the shared 3-node cluster

### After Colima Restart
When restarting Colima, services now start in proper dependency order:
1. Run `make verify-startup` to check service health
2. Dependencies are automatically handled by Flux `dependsOn` clauses
3. Extended timeouts (10-15m) allow for slower startups
4. Health checks prevent services from starting before dependencies are ready

## GitOps Safety and Cross-Environment Protection

### Pre-commit Hooks
```bash
# Install pre-commit hook to prevent cross-environment mistakes
ln -s ../../scripts/pre-commit-check.sh .git/hooks/pre-commit
```

The pre-commit hook automatically:
- Prevents editing production files when on `develop` branch
- Warns when committing directly to `main` branch
- Ensures proper branch-environment alignment

### Local Testing and Validation
```bash
# Validate all changes before committing
./scripts/test-flux-changes.sh

# Check kustomizations and HelmReleases
# Validates syntax and detects common issues like:
# - Duplicate resource names
# - Missing namespaces
# - Invalid YAML syntax
```

### Environment-Specific Configuration
- **cluster-vars-patch.yaml**: Environment-specific overrides for base configurations
- **environment.env**: Base environment variables that can be overridden per environment
- Use patches rather than duplicating entire configurations

### Makefile Targets
```bash
# Available make targets
make help           # Show available targets
make port-forward   # Start port forwarding for all services
make verify-startup # Verify service startup order and health
```