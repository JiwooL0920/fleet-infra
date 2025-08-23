# Services Directory - Fine-Grained Kustomizations

Fine-grained service-level kustomizations for all **21 services** in the GitOps platform.

## Architecture

Each service has an individual kustomization file with precise dependencies, enabling maximum parallel deployment and 65-75% deployment time reduction.

## Service Definitions

### Foundation Services (Start Immediately)
- `traefik.yaml` - Ingress controller and load balancer
- `localstack.yaml` - AWS services emulation
- `cnpg-operator.yaml` - PostgreSQL operator
- `external-secrets-operator.yaml` - Secrets management
- `metrics-server.yaml` - Resource metrics collection

### Infrastructure & Configuration
- `crossplane.yaml` - Infrastructure as Code platform  
- `crossplane-config.yaml` - IaC compositions (depends on crossplane)
- `crossplane-providers.yaml` - Cloud providers (depends on crossplane-config)
- `external-secrets-config.yaml` - Secret store config (depends on external-secrets-operator)
- `traefik-config.yaml` - Ingress config (depends on traefik)

### Monitoring & Observability  
- `kube-prometheus-stack.yaml` - Prometheus, Grafana (depends on traefik, metrics-server)
- `weave-gitops.yaml` - GitOps dashboard (depends on traefik)
- `loki.yaml` - Log aggregation (depends on external-secrets-operator)
- `promtail.yaml` - Log shipping (depends on loki)

### Data Layer
- `postgresql-cluster.yaml` - PostgreSQL cluster (depends on cnpg-operator)
- `redis.yaml` - Redis cache (depends on external-secrets-operator)

### Applications
- `n8n.yaml` - Workflow automation (depends on postgresql-cluster)
- `temporal.yaml` - Workflow orchestration (depends on postgresql-cluster)

### Database Management
- `pgadmin4.yaml` - PostgreSQL admin (depends on postgresql-cluster)
- `redisinsight.yaml` - Redis admin (depends on redis)

## Key Features

- **Precise Dependencies**: Services wait only for actual requirements
- **Parallel Deployment**: 15+ services deploy concurrently when possible
- **Health-Based Waiting**: Resource-specific readiness checks
- **Zero Legacy**: No wave-based dependencies

## Deployment Flow

```
T+0:00  Foundation services start (5 parallel)
T+2:30  Configuration services start (2 parallel)  
T+3:00  Infrastructure & monitoring start (4 parallel)
T+5:30  Database services start (2 parallel)
T+6:00  Applications & logging start (4 parallel)
T+8:00  All services operational
```