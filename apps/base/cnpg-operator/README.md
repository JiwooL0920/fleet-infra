# CNPG Operator - Foundation Service

CloudNative PostgreSQL operator enabling PostgreSQL cluster management in Kubernetes.

## Purpose

- PostgreSQL cluster lifecycle management (provisioning, scaling, backup, recovery)
- Custom Resource Definitions (CRDs) for PostgreSQL clusters
- Automated database maintenance and monitoring
- Foundation service enabling database layer deployment

## Dependencies

- **Depends on**: None (foundation service)
- **Depended on by**: postgresql-cluster (requires CNPG CRDs and operator)