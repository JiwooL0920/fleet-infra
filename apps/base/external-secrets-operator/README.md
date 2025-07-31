# External Secrets Operator

External Secrets Operator for synchronizing secrets from external systems to Kubernetes.

## Purpose

Manages secret synchronization between external secret stores (like AWS Secrets Manager via LocalStack) and Kubernetes secrets.

## Components

- Operator deployment via HelmRelease
- ClusterSecretStore for LocalStack integration
- Push secret configurations for PostgreSQL credentials