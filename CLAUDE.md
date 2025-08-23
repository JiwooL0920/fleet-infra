# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes GitOps infrastructure repository using Flux CD with **fine-grained dependency management**. It manages **21 services** across multi-environment deployment with service-level dependencies enabling **8-12 minute deployments** (down from 30-45 minutes) through intelligent parallel deployment.

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

#### Fine-Grained Service Architecture
**21 services** organized in precise dependency layers enabling maximum parallel deployment:

**Foundation Services (5 - start immediately, no dependencies):**
- **Traefik**: Ingress controller and load balancer
- **LocalStack**: AWS services emulation for development
- **CNPG Operator**: CloudNative PostgreSQL operator
- **External Secrets Operator**: Kubernetes secrets management
- **Metrics Server**: Cluster resource metrics

**Infrastructure & Configuration (5 - depend on foundation):**
- **Crossplane**: Infrastructure as Code platform
- **Crossplane Config/Providers**: IaC compositions and providers
- **External Secrets Config**: ClusterSecretStore configuration
- **Traefik Config**: Ingress middleware and configuration

**Monitoring & Observability (4 - parallel deployment):**
- **Kube-Prometheus-Stack**: Complete monitoring solution (Prometheus, Grafana, AlertManager)
- **Weave GitOps**: GitOps dashboard and management
- **Loki**: Log aggregation system
- **Promtail**: Log shipping agent

**Database Services (2 - depend on operators):**
- **PostgreSQL Cluster**: 3-node HA cluster with automated backups
- **Redis**: In-memory data store with authentication

**Application Services (2 - depend on databases):**
- **N8N**: Workflow automation engine with PostgreSQL backend
- **Temporal**: Workflow orchestration platform with PostgreSQL backend

**Database Management (2 - precise dependencies):**
- **pgAdmin4**: PostgreSQL web interface (depends only on PostgreSQL)
- **RedisInsight**: Redis management interface (depends only on Redis)

**Infrastructure Support:**
- **LocalStack Init**: Secret initialization scripts

#### Database Architecture
- PostgreSQL 16 with CloudNative PG operator
- High availability with 3 instances
- Automated backups to LocalStack S3
- Pre-configured databases: `appdb`, `temporal`, `temporal_visibility`
- Auto-generated secure credentials stored in Kubernetes secrets

### Directory Structure Logic

```
base/services/              # Fine-grained service kustomizations (DEPLOYED SYSTEM)
├── kustomization.yaml      # All 21 services with dependency orchestration  
├── environment.env         # Base environment variables for ConfigMap generation
├── traefik.yaml           # Foundation services (5 - no dependencies)
├── postgresql-cluster.yaml # Database services (2 - depend on operators)  
├── n8n.yaml               # Application services (2 - depend on databases)
└── [18 other services]    # Each with precise service-level dependencies

apps/base/                  # Service Kubernetes manifests (referenced by above)
├── traefik/               # HelmRelease, namespace, kustomization per service
├── postgresql-cluster/    # Individual service definitions
├── n8n/                   # Application configurations  
└── [18 other services]/   # Complete Kubernetes resources per service

clusters/stages/            # Environment-specific configurations
├── dev/clusters/services-amer/  # Development environment
│   ├── flux-system/       # Flux controllers (tracks develop branch)
│   ├── cluster-vars-patch.yaml # Dev-specific overrides
│   └── kustomization.yaml # References base/services/ 
└── prod/                  # Production environment (similar structure, tracks main branch)

scripts/                   # Automation and utilities
├── port-forward.sh        # Service port forwarding
├── verify-startup.sh      # Health verification
└── init-*-secrets.sh      # LocalStack secret initialization
```

**Key Architecture Concepts:**
- **`base/services/`**: Primary deployment system using fine-grained kustomizations
- **`apps/base/`**: Individual service Kubernetes manifests referenced by fine-grained system
- **Service Dependencies**: Each `.yaml` file in `base/services/` declares precise `dependsOn` relationships
- **Parallel Deployment**: 15+ services can deploy concurrently when dependencies are satisfied

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
3. Create service kustomization in `base/services/<app-name>.yaml` with proper dependencies
4. Add to `base/services/kustomization.yaml` resources list
5. Test in development environment first

**Service Kustomization Template:**
```yaml
# base/services/<app-name>.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app-name>
  namespace: flux-system
spec:
  interval: 10m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/base/<app-name>
  prune: true
  wait: true
  timeout: 10m0s
  dependsOn:    # Define precise service dependencies
    - name: <dependency-service>
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars
```

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
- **Fine-grained deployment**: Services deploy via `base/services/kustomization.yaml` with precise dependencies
- **Service dependencies**: Each service kustomization declares exact `dependsOn` relationships
- **Parallel deployment**: 15+ services can deploy concurrently when dependencies are satisfied

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