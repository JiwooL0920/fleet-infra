# ADR-004: Single Shared PostgreSQL Cluster

**Status:** Accepted
**Date:** 2025-01 (implemented), 2026-06 (documented as ADR)

## Context

Multiple services require PostgreSQL: n8n, Temporal (+ visibility), Grafana, kagent, agentic-ai, youtube-automation. Each could have its own database instance or share a cluster.

## Decision

Run a **single CloudNative-PG cluster** (`postgresql-cluster` in `cnpg-system` namespace) with multiple logical databases provisioned declaratively via `apps/base/cloudnative-pg/databases/`.

Current databases: `appdb`, `n8n`, `temporal`, `temporal_visibility`, `grafana`, `kagent`, `agentic-ai`, `youtube-automation`.

Configuration:
- Dev: 1 instance, 10Gi storage
- Prod: 3 instances (HA), 20Gi storage
- PostgreSQL 16, shared resource limits (1-2Gi RAM, 0.5-1 CPU)

## Options Considered

1. **Single shared cluster** (chosen) — One CNPG Cluster, multiple databases. Operator handles HA, backups, failover for all databases at once.

2. **Per-service clusters** — Each app gets its own CNPG Cluster. Better blast radius isolation, independent scaling. But: 6x the operator overhead, 6x the backup configurations, 6x the resource consumption for a dev environment.

3. **Managed database (RDS/Aurora)** — Not applicable for local-first development on Colima/Kind.

## Consequences

### Positive

- Single backup strategy covers all databases (LocalStack S3, daily at 2:00 AM UTC)
- Resource-efficient: one set of replicas serves all workloads
- Simpler operational model: one cluster to monitor, one failover domain
- CNPG operator handles all HA concerns (automatic failover, streaming replication)
- Declarative database provisioning via Kubernetes manifests

### Negative

- Shared blast radius: a cluster-level failure takes down all services simultaneously
- Resource contention: heavy Temporal queries could impact n8n or Grafana
- Cannot independently scale databases (all share the same instance count/resources)
- Connection pooling not per-database (shared `max_connections: 200`)

### Acceptable Because

- Solo developer project — operational simplicity outweighs isolation
- Workloads are light (dev/POC, not production traffic)
- CNPG operator is proven reliable for this scale
- If a service needs isolation later, it can get its own CNPG Cluster without disrupting others
