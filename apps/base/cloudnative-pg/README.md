# CloudNative PostgreSQL - Database Layer

PostgreSQL 16 cluster providing persistent data storage for application services.

## Purpose

- High-availability PostgreSQL 16 cluster with 3 instances
- Automated backups to LocalStack S3 storage
- Pre-configured databases for applications: `appdb`, `temporal`, `temporal_visibility`
- Auto-generated secure credentials stored in Kubernetes secrets

## Dependencies

- **Depends on**: cnpg-operator (CloudNative PostgreSQL operator must be running)
- **Depended on by**: n8n, temporal, pgadmin4 (applications requiring PostgreSQL)

## Components

- `postgresql-cluster.yaml` - Main cluster configuration with HA setup
- `databases/` - Database definitions for applications
- Automated backup configuration to LocalStack S3
