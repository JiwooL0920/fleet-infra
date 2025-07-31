# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes GitOps infrastructure repository using Flux CD for multi-environment deployment. It manages infrastructure applications across development and production environments with complete separation and automated deployments.

## Common Commands

### Local Development Setup
```bash
# Initialize AWS secrets in LocalStack (required for External Secrets)
make init-aws-secrets

# Start port forwarding for all services
make port-forward

# Verify service startup order and health
make verify-startup
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

### Available Scripts
```bash
# Initialize secrets in LocalStack for pgAdmin4 and Redis
./scripts/init-pgadmin-secrets.sh
./scripts/init-redis-secret.sh

# Start port forwarding for all services
./scripts/port-forward.sh

# Verify service startup order and health
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
- **CNPG Operator**: CloudNative PostgreSQL operator for managing PostgreSQL clusters
- **External Secrets Operator**: Manages external secrets integration and synchronization
- **Redis**: In-memory data store with authentication via External Secrets
- **N8N**: Workflow automation engine with PostgreSQL backend (depends on PostgreSQL)
- **Temporal**: Workflow orchestration platform (depends on PostgreSQL)
- **pgAdmin4**: Web-based PostgreSQL database administration tool (depends on PostgreSQL)
- **RedisInsight**: Web-based Redis database administration tool (depends on Redis)
- **Traefik**: Ingress controller and load balancer
- **Kube-Prometheus-Stack**: Monitoring with Grafana, Prometheus, Alertmanager
- **LocalStack**: Local AWS services emulation (required for PostgreSQL backups and External Secrets)
- **Weave GitOps**: GitOps dashboard and management

#### Wave-Based Deployment Architecture
Deployment uses a 5-wave system with dependency management:

**Wave 1: Infrastructure Core** (5m timeout)
- Traefik (ingress and foundational networking)
- LocalStack (AWS services emulation)

**Wave 2: Infrastructure Operators** (10m timeout)
- CNPG Operator (PostgreSQL operator)
- External Secrets Operator (secrets management)

**Wave 3: Infrastructure Configuration**
- Namespace configurations and base settings

**Wave 4: Parallel Deployment** (all depend on Wave 3)
- **Infrastructure Monitoring**: Kube-Prometheus-Stack, Weave GitOps
- **Database Workloads** (15m timeout): PostgreSQL Cluster, Redis
- **Services**: N8N, Temporal

**Wave 5: Database UI** (depends on Database Workloads)
- pgAdmin4 (depends on PostgreSQL)
- RedisInsight (depends on Redis)

#### Database Architecture
- PostgreSQL 16 with CloudNative PG operator
- High availability with 3 instances
- Automated backups to LocalStack S3
- Pre-configured databases: `appdb`, `temporal`, `temporal_visibility`
- Auto-generated secure credentials stored in Kubernetes secrets

### Directory Structure Logic

```
base/                        # Wave-based deployment configurations
├── infrastructure/         # Wave 1-3: Core infrastructure
│   ├── core/              # Traefik, LocalStack
│   ├── operators/         # CNPG, External Secrets operators
│   └── config/            # Configuration and namespaces
├── infrastructure-monitoring.yaml # Wave 4: Monitoring stack
├── database/              # Wave 4-5: Database services
│   ├── workloads/         # PostgreSQL cluster, Redis
│   └── ui/                # pgAdmin4, RedisInsight
└── services.yaml          # Wave 4: Application services (N8N, Temporal)

base/                       # Base Kustomization aggregating all apps
├── kustomization.yaml      # Main kustomization with resource order
├── environment.env         # Base environment variables
├── services/               # Service-specific configurations
└── *.yaml                  # Individual service kustomizations

clusters/stages/            # Environment-specific configurations
├── dev/                    # Development environment
│   ├── base/               # Base dev configurations
│   │   ├── cluster-vars-patch.yaml
│   │   └── kustomization.yaml
│   └── clusters/services-amer/
│       ├── flux-system/    # Flux controllers (tracks develop branch)
│       ├── cluster-vars-patch.yaml
│       └── kustomization.yaml
└── prod/                   # Production environment (similar structure, tracks main branch)

scripts/                    # Automation scripts
├── init-pgadmin-secrets.sh # Initialize pgAdmin4 secrets in LocalStack
├── init-redis-secret.sh    # Initialize Redis secrets in LocalStack
├── port-forward.sh         # Service port forwarding
└── verify-startup.sh       # Service health verification
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
- pgAdmin4: 8080
- PostgreSQL: 5432
- Redis: 6379
- RedisInsight: 8001

## Key Development Workflows

### Making Infrastructure Changes
1. Create feature branch from `develop`
2. Make changes to application configurations
3. Test with Flux dry-run commands:
   ```bash
   flux diff kustomization apps --path ./base
   ```
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
- Use `make init-aws-secrets` before starting services locally
- Monitor Flux reconciliation status when making changes
- PostgreSQL databases are created automatically via database configs in `apps/base/cloudnative-pg/databases/`
- All applications use PostgreSQL from the shared 3-node cluster
- External Secrets Operator manages secret synchronization between external systems and Kubernetes
- Resource deployment order is controlled by the `base/kustomization.yaml` file

### After Colima Restart
When restarting Colima, services now start in proper dependency order:
1. Run `make verify-startup` to check service health
2. Dependencies are automatically handled by Flux `dependsOn` clauses
3. Extended timeouts (10-15m) allow for slower startups
4. Health checks prevent services from starting before dependencies are ready

## Environment-Specific Configuration

### Configuration Management
- **cluster-vars-patch.yaml**: Environment-specific overrides for base configurations
- **environment.env**: Base environment variables that can be overridden per environment
- **ConfigMap substitution**: Uses `postBuild.substituteFrom` for dynamic value injection
- Use patches rather than duplicating entire configurations

### Cross-Environment Safety
- Complete environment isolation using different Git branches
- Development environment tracks `develop` branch
- Production environment tracks `main` branch
- No shared resources between environments

### Makefile Targets
```bash
# Available make targets
make help           # Show available targets
make port-forward   # Start port forwarding for all services
make verify-startup # Verify service startup order and health
make init-aws-secrets # Initialize AWS secrets in LocalStack
```

## External Secrets Integration

### LocalStack Secrets Manager
The repository uses LocalStack to simulate AWS Secrets Manager for local development:
- **pgAdmin4**: Requires `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`
- **Redis**: Requires `REDIS_PASSWORD` for authentication
- **ClusterSecretStore**: Configured to sync secrets from LocalStack to Kubernetes secrets

### Secret Initialization Workflow
```bash
# The init-aws-secrets target automatically:
# 1. Starts LocalStack port forwarding if needed
# 2. Waits for LocalStack health check
# 3. Creates secrets in LocalStack Secrets Manager
# 4. External Secrets Operator syncs them to Kubernetes
```

## Troubleshooting

### Common Issues
```bash
# Check External Secrets Operator status
kubectl get externalsecrets --all-namespaces
kubectl get secretstore --all-namespaces

# Check LocalStack connectivity
curl http://localhost:4566/_localstack/health

# Force secret synchronization
kubectl annotate externalsecret <secret-name> -n <namespace> force-sync=$(date +%s)

# Check Flux reconciliation status
flux get all --status-selector ready=false
```