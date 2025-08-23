# Base Directory - Fine-Grained GitOps System

Fine-grained service-level deployment configurations for the fleet infrastructure.

## Architecture

Orchestrates **21 services** using precise service-level dependencies for optimal parallel deployment, eliminating the need for coarse wave-based waiting.

## Structure

- `services/` - **Fine-grained service kustomizations** (primary deployment method)
  - Individual service definitions with precise dependencies
  - Parallel deployment opportunities maximized
  - 8-12 minute deployment times achieved

## Services Directory

Contains individual `.yaml` files for each of the 21 services:

### Foundation (No Dependencies)

- `traefik.yaml`, `localstack.yaml`, `cnpg-operator.yaml`, `external-secrets-operator.yaml`, `metrics-server.yaml`

### Infrastructure & Configuration

- `crossplane.yaml`, `crossplane-config.yaml`, `crossplane-providers.yaml`
- `external-secrets-config.yaml`, `traefik-config.yaml`

### Monitoring & Observability

- `kube-prometheus-stack.yaml`, `weave-gitops.yaml`, `loki.yaml`, `promtail.yaml`

### Data & Applications

- `postgresql-cluster.yaml`, `redis.yaml`, `n8n.yaml`, `temporal.yaml`

### Database Management

- `pgadmin4.yaml`, `redisinsight.yaml`

