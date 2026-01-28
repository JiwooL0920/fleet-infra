# Apps Directory

Contains application-specific Kubernetes configurations for the fine-grained GitOps architecture.

## Architecture

The apps directory contains **16 active services** (21 total, 5 disabled) organized with individual application configurations that are referenced by the fine-grained dependency management system in `/base/services/`.

## Structure

- `base/` - Individual application Kubernetes manifests
  - Each subdirectory contains a specific service's configurations
  - HelmReleases, namespaces, ExternalSecrets, and service-specific resources
  - Environment-agnostic base configurations referenced by fine-grained kustomizations
  - 21 service directories total (16 deployed by default)

## Service Categories

### Foundation Services (7 Active)
- **traefik/**: Ingress controller and load balancer
- **localstack/**: AWS services emulation
- **cnpg-operator/**: PostgreSQL operator
- **external-secrets-operator/**: Secrets management operator
- **external-secrets-config/**: ClusterSecretStore configuration
- **traefik-config/**: Ingress middleware and configuration
- **metrics-server/**: Resource metrics collection

### Infrastructure & Configuration (3 Disabled)
- **crossplane/**: Infrastructure as Code platform (disabled)
- **crossplane-providers/**: Cloud provider configurations (disabled)
- **crossplane-config/**: Composition definitions (disabled)

### Monitoring & Observability (2 Active, 2 Disabled)
- **kube-prometheus-stack/**: Prometheus, Grafana, AlertManager
- **weave-gitops/**: GitOps dashboard
- **loki/**: Log aggregation system (disabled)
- **promtail/**: Log shipping agent (disabled)

### Data Layer (2 Active)
- **cloudnative-pg/**: PostgreSQL cluster definitions
- **redis-sentinel/**: Redis cache with Sentinel HA

### Applications (2 Active)
- **n8n/**: Workflow automation platform
- **temporal/**: Workflow orchestration engine

### Database Management (2 Active)
- **pgadmin4/**: PostgreSQL web interface
- **redisinsight/**: Redis management interface

### Infrastructure Support
- **localstack-init/**: LocalStack initialization scripts

## Deployment Model

Applications are deployed via fine-grained kustomizations in `/base/services/` that reference these base configurations with precise service-level dependencies rather than coarse wave-based dependencies. Services can be enabled/disabled by commenting/uncommenting them in `/base/services/kustomization.yaml`.
