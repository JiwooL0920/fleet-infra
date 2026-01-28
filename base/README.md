# Base Directory - Fine-Grained GitOps System

Fine-grained service-level deployment configurations for the fleet infrastructure.

## Architecture

Orchestrates **16 active services** (21 total, 5 disabled) using precise service-level dependencies for optimal parallel deployment, eliminating the need for coarse wave-based waiting.

## Structure

- `services/` - **Fine-grained service kustomizations** (primary deployment method)
  - Individual service definitions with precise dependencies
  - Parallel deployment opportunities maximized
  - 8-12 minute deployment times achieved
  - Flexible service enable/disable capability

## Services Directory

Contains individual `.yaml` files for each of the 21 services (16 active by default):

### Active Services

#### Foundation (No Dependencies)

- `traefik.yaml`, `localstack.yaml`, `cnpg-operator.yaml`, `external-secrets-operator.yaml`, `external-secrets-config.yaml`, `traefik-config.yaml`, `metrics-server.yaml`

#### Monitoring & Observability

- `kube-prometheus-stack.yaml`, `weave-gitops.yaml`

#### Data & Applications

- `postgresql-cluster.yaml`, `redis-sentinel.yaml`, `n8n.yaml`, `temporal.yaml`

#### Database Management

- `pgadmin4.yaml`, `redisinsight.yaml`

### Disabled Services (Available for Deployment)

- `crossplane.yaml`, `crossplane-config.yaml`, `crossplane-providers.yaml` (Infrastructure as Code)
- `loki.yaml`, `promtail.yaml` (Log aggregation stack)
