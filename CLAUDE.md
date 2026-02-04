# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes GitOps infrastructure repository using Flux CD with **fine-grained dependency management**. It manages **19 active services** across multi-environment deployment with service-level dependencies enabling **8-12 minute deployments** (down from 30-45 minutes) through intelligent parallel deployment.

**Note**: 5 services are currently disabled (Crossplane suite, Loki, Promtail) and can be re-enabled as needed.

## Common Commands

### Local Development Setup
```bash
# Setup local DNS entries for Traefik ingress (RECOMMENDED)
make setup-dns

# Alternative: Start port forwarding for all services
make port-forward

# Fix control plane IP after Colima restart
make fix-control-plane

# Complete post-restart setup
make post-colima-restart
```

**Note:** Secrets are automatically initialized by LocalStack startup hooks. No manual initialization needed.

### Accessing Services

**Option 1: Local DNS (Recommended)**
```bash
# One-time setup: Add .local domain entries to /etc/hosts
make setup-dns

# Access services via Traefik at .local domains:
# http://traefik.local - Traefik Dashboard
# http://grafana.local - Grafana
# http://prometheus.local - Prometheus
# http://alertmanager.local - AlertManager
# http://n8n.local - N8N
# http://temporal.local - Temporal UI
# http://pgadmin.local - pgAdmin4
# http://redis.local - RedisInsight
# http://weave.local - Weave GitOps
# http://localstack.local - LocalStack
# http://scylla.local - ScyllaDB Alternator (DynamoDB API)
```

**Option 2: Port Forwarding**
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

# Check ScyllaDB cluster
kubectl get scyllacluster -n scylla
kubectl get pods -n scylla
kubectl get pods -n scylla-operator
kubectl get pods -n scylla-manager

# Test ScyllaDB Alternator endpoint (DynamoDB API)
curl http://scylla.local/
```

### Available Scripts
```bash
# Setup local DNS entries for Traefik ingress
./scripts/setup-local-dns.sh

# Start port forwarding for all services
./scripts/port-forward.sh

# Fix control plane IP after Colima restart
./scripts/fix-control-plane-ip.sh

# Validate Kustomize configurations
./scripts/validate-kustomize.sh

# Validate Kubernetes manifests
./scripts/validate-manifests.sh
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
**19 active services** organized in precise dependency layers enabling maximum parallel deployment:

**Foundation Services (8 - start immediately, no dependencies):**
- **Traefik**: Ingress controller and load balancer
- **LocalStack**: AWS services emulation for development
- **CNPG Operator**: CloudNative PostgreSQL operator
- **Scylla Operator**: ScyllaDB Kubernetes operator for managing clusters
- **External Secrets Operator**: Kubernetes secrets management
- **External Secrets Config**: ClusterSecretStore configuration
- **Traefik Config**: Ingress middleware and configuration
- **Metrics Server**: Cluster resource metrics

**Monitoring & Observability (2 - depend on foundation):**
- **Kube-Prometheus-Stack**: Complete monitoring solution (Prometheus, Grafana, AlertManager)
- **Weave GitOps**: GitOps dashboard and management

**Database Management Services (1 - depend on operators):**
- **Scylla Manager**: ScyllaDB backup and repair automation

**Database Services (3 - depend on operators):**
- **PostgreSQL Cluster**: HA cluster with automated backups (1 instance in dev, 3 in prod)
- **Redis Sentinel**: In-memory data store with authentication and HA
- **ScyllaDB Cluster**: NoSQL database with Alternator (DynamoDB API) for chat history

**Application Services (3 - depend on databases):**
- **N8N**: Workflow automation engine with PostgreSQL backend
- **Temporal**: Workflow orchestration platform with PostgreSQL backend

**Database Management UIs (2 - precise dependencies):**
- **pgAdmin4**: PostgreSQL web interface (depends only on PostgreSQL)
- **RedisInsight**: Redis management interface (depends only on Redis)

**Disabled Services (available but not deployed):**
- **Crossplane**: Infrastructure as Code platform (disabled)
- **Crossplane Config/Providers**: IaC compositions and providers (disabled)
- **Loki**: Log aggregation system (disabled)
- **Promtail**: Log shipping agent (disabled)

#### Database Architecture
- PostgreSQL 16 with CloudNative PG operator
- High availability: 1 instance in dev, 3 instances in production
- Automated backups to LocalStack S3
- Pre-configured databases: `appdb`, `n8n`, `temporal`, `temporal_visibility`
- Auto-generated secure credentials stored in Kubernetes secrets
- Redis Sentinel HA with master-replica configuration
- ScyllaDB with Alternator (DynamoDB-compatible API) for chat history and session storage
  - Discord-proven at trillion+ message scale
  - Native TTL support for automatic data retention
  - Scylla Manager for backup and repair automation

### Directory Structure Logic

```
base/services/              # Fine-grained service kustomizations (DEPLOYED SYSTEM)
├── kustomization.yaml      # 19 active services with dependency orchestration
├── environment.env         # Base environment variables for ConfigMap generation
├── traefik.yaml           # Foundation services (8 - no dependencies)
├── scylla-operator.yaml   # ScyllaDB operator (foundation)
├── scylla-manager.yaml    # ScyllaDB backup/repair (depends on operator)
├── scylla-cluster.yaml    # ScyllaDB with Alternator (depends on operator + manager)
├── postgresql-cluster.yaml # Database services (3 - depend on operators)
├── n8n.yaml               # Application services (3 - depend on databases)
└── [13 other services]    # Each with precise service-level dependencies

apps/base/                  # Service Kubernetes manifests (referenced by above)
├── traefik/               # HelmRelease, namespace, kustomization per service
├── scylla-operator/       # ScyllaDB Kubernetes operator
├── scylla-manager/        # ScyllaDB backup and repair automation
├── scylla/                # ScyllaDB cluster with Alternator
├── postgresql-cluster/    # Individual service definitions (cloudnative-pg)
├── n8n/                   # Application configurations
└── [18 other services]/   # Complete Kubernetes resources per service (includes disabled)

clusters/stages/            # Environment-specific configurations
├── dev/clusters/services-amer/  # Development environment
│   ├── flux-system/       # Flux controllers (tracks develop branch)
│   ├── cluster-vars-patch.yaml # Dev-specific overrides
│   └── kustomization.yaml # References base/services/
└── prod/                  # Production environment (similar structure, tracks main branch)

scripts/                   # Automation and utilities
├── port-forward.sh        # Service port forwarding
├── setup-local-dns.sh     # Local DNS entries for Traefik ingress
├── fix-control-plane-ip.sh # Fix control plane IP after Colima restart
├── validate-kustomize.sh  # Validate Kustomize configurations
└── validate-manifests.sh  # Validate Kubernetes manifests
```

**Key Architecture Concepts:**
- **`base/services/`**: Primary deployment system using fine-grained kustomizations
- **`apps/base/`**: Individual service Kubernetes manifests referenced by fine-grained system
- **Service Dependencies**: Each `.yaml` file in `base/services/` declares precise `dependsOn` relationships
- **Parallel Deployment**: 10+ services can deploy concurrently when dependencies are satisfied
- **Local DNS**: Use Traefik ingress with .local domains instead of port forwarding (recommended)

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
- Loki: 3100 (service disabled by default)
- Weave GitOps: 9001
- Temporal UI: 8090
- pgAdmin4: 8080
- PostgreSQL: 5432
- Redis Sentinel: 6379
- RedisInsight: 8001

### Domain Mappings (when using local DNS - recommended)
- Traefik Dashboard: http://traefik.local
- Grafana: http://grafana.local
- Prometheus: http://prometheus.local
- AlertManager: http://alertmanager.local
- N8N: http://n8n.local
- Temporal UI: http://temporal.local
- pgAdmin4: http://pgadmin.local
- RedisInsight: http://redis.local
- Weave GitOps: http://weave.local
- LocalStack: http://localstack.local
- ScyllaDB Alternator: http://scylla.local

## Key Development Workflows

### Accessing Services Locally

**Recommended: Traefik Ingress with Local DNS**
1. One-time setup: `make setup-dns` (adds .local domains to /etc/hosts)
2. Access all services via friendly domain names (e.g., http://grafana.local)
3. Traefik handles routing automatically
4. No need to remember port numbers

**Alternative: Port Forwarding**
1. Run `make port-forward` to start forwarding all service ports
2. Access services at localhost with specific ports
3. Requires keeping port-forward process running

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

### Enabling/Disabling Services
To disable a service, comment it out in `base/services/kustomization.yaml`:
```yaml
resources:
  # - crossplane.yaml  # Disabled - uncomment to enable
```

To enable a disabled service, uncomment it in `base/services/kustomization.yaml` and commit the change. The service will deploy automatically after Flux reconciliation.

### Environment Configuration Differences
- Use cluster-vars-patch.yaml and environment.env files for environment-specific overrides
- Base configurations in `apps/base/` should be environment-agnostic
- Environment-specific values in `clusters/stages/*/clusters/services-amer/`
- **Development**: Cost-optimized (single replicas, reduced resources, shorter retention)
  - PostgreSQL: 1 instance, 10Gi storage, 7-day backup retention
  - Redis: 1 replica, 8Gi storage
  - Prometheus: 20Gi storage, 7-day retention
  - Traefik: 1 replica
- **Production**: High availability (multiple replicas, full resources, extended retention)
  - PostgreSQL: 3 instances, 20Gi storage, 30-day backup retention
  - Redis: 2+ replicas, larger storage
  - Prometheus: 50Gi storage, 30-day retention
  - Traefik: 3 replicas

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
- **Secrets are automatically initialized by LocalStack** - no manual initialization needed
- Monitor Flux reconciliation status when making changes
- PostgreSQL databases are created automatically via database configs in `apps/base/cloudnative-pg/databases/`
- All applications use PostgreSQL from the shared cluster (1 instance in dev, 3 in prod)
- External Secrets Operator manages secret synchronization between external systems and Kubernetes
- **Fine-grained deployment**: Services deploy via `base/services/kustomization.yaml` with precise dependencies
- **Service dependencies**: Each service kustomization declares exact `dependsOn` relationships
- **Parallel deployment**: 10+ services can deploy concurrently when dependencies are satisfied
- **Local DNS recommended**: Use `make setup-dns` for better UX than port forwarding
- **Disabled services**: Crossplane (IaC), Loki, and Promtail are available but not deployed by default

### After Colima Restart
When restarting Colima, services start automatically in proper dependency order:
1. Run `make post-colima-restart` to fix control plane IP configuration
2. Dependencies are automatically handled by Flux `dependsOn` clauses
3. Extended timeouts (10-15m) allow for slower startups
4. Health checks prevent services from starting before dependencies are ready
5. Secrets are automatically restored from LocalStack persistence

**Optional**: Run `make setup-dns` once to enable accessing services via .local domains instead of port forwarding.

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
make help                # Show available targets
make setup-dns           # Setup local DNS entries for Traefik ingress (recommended)
make port-forward        # Start port forwarding for all services (alternative to DNS)
make fix-control-plane   # Fix control plane IP after Colima restart
make post-colima-restart # Complete post-restart setup (fix IP only)
```

## External Secrets Integration

### LocalStack Secrets Manager
The repository uses LocalStack to simulate AWS Secrets Manager for local development with **automatic secret initialization**:

- **Automatic Initialization**: Secrets are created via LocalStack startup hooks (`enableStartupScripts`)
- **Persistence**: LocalStack persists secrets across pod restarts
- **Idempotent**: Startup scripts check for existing secrets before creating new ones
- **ClusterSecretStore**: External Secrets Operator syncs from LocalStack to Kubernetes secrets

### Secrets Created Automatically
- **Crossplane**: AWS credentials for infrastructure provisioning (service disabled)
- **Redis Sentinel**: Authentication password
- **pgAdmin4**: Admin email and password
- **Grafana**: Admin username and password
- **Traefik**: Dashboard credentials (username, password, htpasswd)

### Verifying Secrets
```bash
# Port forward to LocalStack
kubectl port-forward -n localstack svc/localstack 4566:4566

# List all secrets
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets --region us-east-1

# Get a specific secret
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id redis/credentials/password --region us-east-1
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

# Check HelmRelease status
kubectl get helmrelease --all-namespaces

# View service logs
kubectl logs -n <namespace> <pod-name> -f

# Check PostgreSQL cluster status
kubectl get cluster -n cnpg-system
kubectl describe cluster postgresql-cluster -n cnpg-system

# Check Redis Sentinel status
kubectl get pods -n redis-sentinel
kubectl logs -n redis-sentinel <redis-pod-name>

# Check ScyllaDB status
kubectl get scyllacluster -n scylla
kubectl describe scyllacluster scylla -n scylla
kubectl logs -n scylla <scylla-pod-name>
```

### Service Access Issues
If services are not accessible via .local domains:
1. Verify DNS entries: `cat /etc/hosts | grep "Kubernetes local services"`
2. Re-run setup if needed: `make setup-dns`
3. Check Traefik is running: `kubectl get pods -n traefik`
4. Verify Traefik IngressRoutes: `kubectl get ingressroute --all-namespaces`

If port forwarding fails:
1. Check service exists: `kubectl get svc -n <namespace>`
2. Kill processes on occupied ports: `lsof -ti:<port> | xargs kill -9`
3. Restart port forwarding: `make port-forward`
