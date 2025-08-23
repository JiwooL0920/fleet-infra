# Apps Directory

Contains application-specific Kubernetes configurations for the fine-grained GitOps architecture.

## Architecture

The apps directory contains **21 services** organized with individual application configurations that are referenced by the fine-grained dependency management system in `/base/services/`.

## Structure

- `base/` - Individual application Kubernetes manifests
  - Each subdirectory contains a specific service's configurations
  - HelmReleases, namespaces, ExternalSecrets, and service-specific resources
  - Environment-agnostic base configurations referenced by fine-grained kustomizations

## Service Categories

### Foundation Services (5)
- **traefik/**: Ingress controller and load balancer
- **localstack/**: AWS services emulation
- **cnpg-operator/**: PostgreSQL operator
- **external-secrets-operator/**: Secrets management operator
- **metrics-server/**: Resource metrics collection

### Infrastructure & Configuration (5)  
- **crossplane/**: Infrastructure as Code platform
- **crossplane-providers/**: Cloud provider configurations
- **crossplane-config/**: Composition definitions
- **external-secrets-config/**: ClusterSecretStore configuration
- **traefik-config/**: Ingress middleware and configuration

### Monitoring & Observability (3)
- **kube-prometheus-stack/**: Prometheus, Grafana, AlertManager
- **weave-gitops/**: GitOps dashboard
- **loki/**: Log aggregation system
- **promtail/**: Log shipping agent

### Data Layer (2)
- **cloudnative-pg/**: PostgreSQL cluster definitions
- **redis/**: Redis cache with authentication

### Applications (2)
- **n8n/**: Workflow automation platform  
- **temporal/**: Workflow orchestration engine

### Database Management (2)
- **pgadmin4/**: PostgreSQL web interface
- **redisinsight/**: Redis management interface

### Infrastructure Support (2)
- **infrastructure/**: Shared infrastructure components
- **localstack-init/**: LocalStack initialization scripts

## Deployment Model

Applications are deployed via fine-grained kustomizations in `/base/services/` that reference these base configurations with precise service-level dependencies rather than coarse wave-based dependencies.