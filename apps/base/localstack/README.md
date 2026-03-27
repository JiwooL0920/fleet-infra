# LocalStack - Foundation Service

Local AWS services emulation providing S3 storage and Secrets Manager for development.

## Purpose

- AWS S3 emulation for PostgreSQL automated backups
- AWS Secrets Manager emulation for External Secrets integration
- Local development environment eliminating need for real AWS resources
- Foundation service enabling backup and secret management capabilities

## Dependencies

- **Depends on**: None (foundation service)
- **Depended on by**: postgresql-cluster (backup storage), external-secrets-config (secrets store)
