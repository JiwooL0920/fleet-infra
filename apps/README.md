# Apps Directory

Contains application-specific Kubernetes configurations organized by service.

## Structure

- `base/` - Base Kustomization configurations for all applications
  - Each subdirectory contains a specific application's Kubernetes manifests
  - Includes HelmReleases, namespaces, and service-specific configurations
  - Environment-agnostic base configurations that can be customized per environment

## Applications Included

- CloudNative PostgreSQL with database configurations
- CNPG Operator for PostgreSQL management
- External Secrets Operator for secret synchronization
- Monitoring stack (Kube-Prometheus-Stack)
- Infrastructure services (LocalStack, Traefik)
- Application services (N8N, Temporal, pgAdmin4, Redis, RedisInsight)
- GitOps management (Weave GitOps)