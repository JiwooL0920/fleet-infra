# Services Directory - Fine-Grained Kustomizations

Fine-grained service-level kustomizations for the GitOps platform.

**Note:** Service enablement is controlled in `kustomization.yaml`; see `../../service-catalog.json` for the current enabled/disabled inventory.

## Architecture

Each service has an individual kustomization file with precise dependencies, enabling maximum parallel deployment and 65-75% deployment time reduction.

## Service Definitions

### Foundation Services (Start Immediately)
- `traefik.yaml` - Ingress controller and load balancer
- `localstack.yaml` - AWS services emulation
- `cnpg-operator.yaml` - PostgreSQL operator
- `external-secrets-operator.yaml` - Secrets management
- `external-secrets-config.yaml` - Secret store config
- `traefik-config.yaml` - Ingress config
- `metrics-server.yaml` - Resource metrics collection

### Infrastructure & Configuration (Disabled)
- `crossplane.yaml` - Infrastructure as Code platform (disabled)
- `crossplane-config.yaml` - IaC compositions (disabled)
- `crossplane-providers.yaml` - Cloud providers (disabled)

### Monitoring & Observability
- `kube-prometheus-stack.yaml` - Prometheus, Grafana (depends on traefik, metrics-server)
- `weave-gitops.yaml` - GitOps dashboard (depends on traefik)
- `loki.yaml` - Log aggregation (disabled)
- `promtail.yaml` - Log shipping (disabled)

### Data Layer
- `postgresql-cluster.yaml` - PostgreSQL cluster (depends on cnpg-operator)
- `redis-sentinel.yaml` - Redis cache with Sentinel HA (depends on external-secrets-operator)

### Applications
- `n8n.yaml` - Workflow automation (depends on postgresql-cluster)
- `temporal.yaml` - Workflow orchestration (depends on postgresql-cluster)

### Database Management
- `pgadmin4.yaml` - PostgreSQL admin (depends on postgresql-cluster)
- `redisinsight.yaml` - Redis admin (depends on redis-sentinel)

## Key Features

- **Precise Dependencies**: Services wait only for actual requirements
- **Parallel Deployment**: 10+ services deploy concurrently when possible
- **Health-Based Waiting**: Resource-specific readiness checks
- **Zero Legacy**: No wave-based dependencies
- **Flexible Service Management**: Easily enable/disable services as needed

## Deployment Flow

```
T+0:00  Foundation services start (7 parallel)
T+2:30  Monitoring services start (2 parallel)
T+5:30  Database services start (2 parallel)
T+6:00  Applications start (3 parallel)
T+7:00  Database management start (2 parallel)
T+8:00  All services operational
```

## Enabling/Disabling Services

To disable a service, comment it out in `kustomization.yaml`:
```yaml
resources:
  # - crossplane.yaml  # Disabled
```

To enable, uncomment and commit. Flux will reconcile automatically.
