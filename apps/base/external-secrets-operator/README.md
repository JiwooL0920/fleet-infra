# External Secrets Operator - Foundation Service

Kubernetes secrets management operator enabling secure credential synchronization from external stores.

## Purpose

- Synchronizes secrets from external stores (LocalStack AWS Secrets Manager) to Kubernetes
- Provides ClusterSecretStore and ExternalSecret CRDs
- Enables secure credential management across all services
- Foundation service for secret management capabilities

## Dependencies

- **Depends on**: None (foundation service)
- **Depended on by**: external-secrets-config, redis, loki, kube-prometheus-stack (services requiring secret synchronization)

## Components

- External Secrets operator deployment via HelmRelease
- ClusterSecretStore for LocalStack integration
- Push secret configurations for PostgreSQL credentials
- Namespace and RBAC configurations
