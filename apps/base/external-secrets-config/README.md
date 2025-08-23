# External Secrets Configuration - Infrastructure Configuration

ClusterSecretStore and base configurations for External Secrets Operator.

## Purpose

- ClusterSecretStore configuration for LocalStack AWS Secrets Manager integration
- Base secret management configurations used across all services
- Common ExternalSecret templates and patterns
- Enables services to synchronize secrets from LocalStack

## Dependencies

- **Depends on**: external-secrets-operator (requires ESO CRDs and operator running)
- **Depended on by**: Services using ExternalSecrets (redis, loki, etc.)