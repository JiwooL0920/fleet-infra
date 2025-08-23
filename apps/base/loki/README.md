# Loki - Logging Infrastructure

Log aggregation system providing centralized logging for all cluster services.

## Purpose

- Centralized log aggregation and storage for all applications and infrastructure
- Label-based log indexing for efficient log queries
- Integration with Grafana for log visualization
- S3-compatible storage backend via LocalStack
- Secure configuration via External Secrets

## Dependencies

- **Depends on**: external-secrets-operator (requires ESO for secure S3 credentials)
- **Depended on by**: promtail (log shipping agent requires Loki for log forwarding)