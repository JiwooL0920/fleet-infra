# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes GitOps infrastructure repository using Flux CD with **fine-grained dependency management**. It manages **several dozen services** across multi-environment deployment with service-level dependencies enabling **8-12 minute deployments** (down from 30-45 minutes) through intelligent parallel deployment. See `service-catalog.json` for the current enabled/disabled inventory.

**Note**: 4 services are currently disabled (Crossplane suite, Scylla Manager) and can be re-enabled as needed.

## Common Commands

For prerequisites, local bootstrap, Flux bootstrap, and local service access quickstart, see `README.md`.

Use this file for architecture context and operations runbook details.

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
**Several dozen services** organized in precise dependency layers enabling maximum parallel deployment (see `service-catalog.json` for current counts):

**Foundation Services (8 - start immediately, no dependencies):**
- **Traefik**: Ingress controller and load balancer
- **LocalStack**: AWS services emulation for development
- **CNPG Operator**: CloudNative PostgreSQL operator
- **Scylla Operator**: ScyllaDB Kubernetes operator for managing clusters
- **External Secrets Operator**: Kubernetes secrets management
- **External Secrets Config**: ClusterSecretStore configuration
- **Traefik Config**: Ingress middleware and configuration
- **Metrics Server**: Cluster resource metrics

**Monitoring & Observability (3 - depend on foundation):**
- **Kube-Prometheus-Stack**: Complete monitoring solution (Prometheus, Grafana, AlertManager)
- **Weave GitOps**: GitOps dashboard and management
- **Argo CD**: Hub-only controller; syncs workloads into a separate **dev-applications** Kind cluster from the `argocd-applications` Git repo (`develop` → `metadata/dev-applications/`). Uses **external Redis** pointing at the shared Sentinel stack's standard ClusterIP (`redis-sentinel.redis-sentinel.svc.cluster.local:6379`) instead of chart-managed Redis. See ADR-013 and ADR-015.

**Logging & Tracing (4 - depend on foundation/monitoring):**
- **Loki**: Log aggregation system
- **Promtail**: Log shipping agent (DaemonSet)
- **Jaeger**: Distributed tracing backend
- **OpenTelemetry Collector**: Unified telemetry collection pipeline (traces, metrics, logs)

**Security & Cost Observability (2 - depend on kube-prometheus-stack):**
- **Kubescape**: Kubernetes security scanning — CVE detection, RBAC audit, misconfiguration checks
- **OpenCost**: Kubernetes cost monitoring with built-in MCP server — feeds finops-agent

**Database Management Services (1 - depend on operators):**
- **Scylla Manager**: ScyllaDB backup and repair automation

**Database Services (3 - depend on operators):**
- **PostgreSQL Cluster**: HA cluster (1 instance in dev, 3 in prod)
- **Redis Sentinel**: In-memory data store with authentication and HA
- **ScyllaDB Cluster**: NoSQL database with Alternator (DynamoDB API) for chat history

**Application Services (3 - depend on databases):**
- **N8N**: Workflow automation engine with PostgreSQL backend
- **Temporal**: Workflow orchestration platform with PostgreSQL backend

**AI Agent Platform (2 - orchestrator-worker multi-agent system):**
- **Ollama**: Local LLM inference backend (foundation, no deps)
- **kagent**: Kubernetes-native AI agent platform (CNCF Sandbox) with 8 specialized agents

**Database Management UIs (2 - precise dependencies):**
- **pgAdmin4**: PostgreSQL web interface (depends only on PostgreSQL)
- **RedisInsight**: Redis management interface (depends only on Redis)

**Disabled Services (available but not deployed):**
- **Crossplane**: Infrastructure as Code platform (disabled)
- **Crossplane Config/Providers**: IaC compositions and providers (disabled)
- **Scylla Manager**: ScyllaDB backup and repair automation (disabled)

#### kagent Multi-Agent Architecture (Orchestrator-Worker Pattern)

kagent implements an **orchestrator-worker pattern** based on Anthropic/LangChain 2026 best practices. A single `coordinator-agent` is the entry point; it delegates to specialized subagents in parallel via the A2A protocol.

**coordinator-agent (single entry point)**
- Analyzes query complexity, decomposes into subtasks, spawns subagents in parallel
- Uses `default-model-config` (qwen2.5:72b) for planning and delegation
- Delegates GitOps changes to gitops-agent via A2A

**Specialized Subagents (use fast-model-config):**
- **k8s-agent**: Pod status, deployments, events, cluster troubleshooting (18 tools). Write tools approval-gated.
- **observability-agent**: Prometheus metrics, Loki logs, Grafana dashboards (mcp-grafana + k8s tools)
- **gitops-agent**: Creates draft PRs in fleet-infra via GitHub MCP. All write tools approval-gated. **Never merges** — humans always merge.
- **flux-agent**: Flux sync status, kustomization health, reconciliation triggers (k8s tools querying Flux CRDs)
- **helm-agent**: Read-only Helm release inspection (values, history, status). Write tools excluded.
- **security-agent**: RBAC audit, Kubescape CVE/misconfiguration CRDs, pod security contexts, network policies
- **finops-agent**: Cost analysis via OpenCost MCP + Prometheus utilization for right-sizing recommendations

**GitOps principle enforced across all agents:**
- No agent applies changes directly to the cluster
- All changes flow through gitops-agent → GitHub PR → human review → merge → Flux reconcile

**GitHub PAT bootstrap (one-time):**
```bash
make setup-github-secret  # Reads GITHUB_TOKEN from env, creates K8s Secret in localstack ns
```
LocalStack startup script reads GITHUB_PAT env var and creates `github/mcp/token` in Secrets Manager.
ExternalSecrets syncs it to `github-mcp-credentials` in kagent namespace.

#### Database Architecture
- PostgreSQL 16 with CloudNative PG operator
- High availability: 1 instance in dev, 3 instances in production
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
├── kustomization.yaml      # Service list with dependency orchestration
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
├── register-app-cluster.sh # Spoke kubeconfig token -> LocalStack for Argo CD cluster secret
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

### Hub cluster and application spoke (local)
- **Hub** (`dev-services-amer`, Flux): hosts platform services plus **Argo CD**. Application manifests for the spoke live in **`argocd-applications`** (not this repo): `develop` / `metadata/dev-applications/`, `main` / `metadata/prod-applications/`.
- **Spoke** (`dev-applications`, no Flux): second Kind cluster from [terraform-infra](https://github.com/JiwooL0920/terraform-infra); Argo CD on the hub reaches its API at `https://dev-applications-control-plane:6443` over the Docker `kind` network. One-time: `make register-app-cluster` (token via LocalStack + ExternalSecret).

### Local Access

For local access to services, use:
- `make setup-dns` (Traefik ingress, .local domains)
- `make port-forward` (traditional port-forward)

See `scripts/port-forward.sh` for canonical port assignments.

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
- Argo CD: http://argocd.local
- LocalStack: http://localstack.local
- ScyllaDB Alternator: http://scylla.local
- Jaeger Tracing UI: http://jaeger.local

## Key Development Workflows

For onboarding workflows (local access options, infra change flow, adding new applications, enabling/disabling services), see `README.md`.

This file remains the deep reference for architecture and operations/troubleshooting.

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
- CNPG backup configuration (`barmanObjectStore` + `ScheduledBackup`) is deferred for the current POC cluster.
- If backup/recovery objectives become required, add CNPG backup manifests and update this section/ADR accordingly.

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
- **Disabled services**: Crossplane (IaC) and Scylla Manager are available but not deployed by default

### After Colima Restart
When restarting Colima, services start automatically in proper dependency order:
1. Run `make post-colima-restart` to fix control plane IP configuration
2. Run `./scripts/refresh-credentials.sh` to fix credential drift (Grafana admin password, CNPG passwords, ExternalSecrets sync)
3. Dependencies are automatically handled by Flux `dependsOn` clauses
4. Extended timeouts (10-15m) allow for slower startups
5. Health checks prevent services from starting before dependencies are ready
6. Secrets are automatically restored from LocalStack persistence

**Credential Self-Healing**:
- **Grafana SA token** (`apps/base/grafana-sa-setup/job.yaml`): One-shot Job with `ttlSecondsAfterFinished: 300` for pod cleanup. Validates existing token before creating a new one to avoid churn. Re-runs automatically on cluster restart (Flux recreates completed Jobs whose pods were cleaned up by TTL).
- **Grafana admin password**: Stored in PostgreSQL (persists), but may drift from K8s secret. `refresh-credentials.sh` resets it via `grafana cli admin reset-admin-password`.
- **Grafana login lockout**: If too many failed auth attempts (e.g., sidecars retrying with wrong password), clear with: `kubectl exec -n cnpg-system postgresql-cluster-1 -c postgres -- psql -U postgres -d grafana -c "DELETE FROM login_attempt;"`
- **kagent Grafana token flow**: LocalStack (`kagent/grafana/api-key`) → ExternalSecret (`kagent-grafana-sa-token` in flux-system) → postBuild substitution → kagent HelmRelease (`KAGENT_GRAFANA_API_KEY`)
- **kagent Loki time parsing**: mcp-grafana's `loki.go` only accepts RFC3339 timestamps (upstream bug — `parseRFC3339OrZero` vs `parseStartTime`/`parseEndTime` used by other datasources). Agent prompts instruct LLMs to compute RFC3339 before calling Loki tools. Upstream fix: swap to `time_helpers.go` parsers in `grafana/mcp-grafana`.

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
For day-1/day-2 command usage, see `README.md`. Keep this section focused on architecture and runbook context.

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
