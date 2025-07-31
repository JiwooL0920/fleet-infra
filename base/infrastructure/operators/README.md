# Infrastructure Operators

Wave 2 Kubernetes operators for platform management.

## Purpose

Deploys operators that manage complex application lifecycles and provide platform capabilities.

## Operators

- `cnpg-operator.yaml` - CloudNative PostgreSQL operator for database management
- `external-secrets-operator.yaml` - External secrets synchronization operator

These operators have extended timeout (10m) to allow for CRD installation and controller startup.