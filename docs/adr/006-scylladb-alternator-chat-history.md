# ADR-006: ScyllaDB with Alternator for Chat History

**Status:** Accepted
**Date:** 2025 (implemented), 2026-06 (documented as ADR)

## Context

The kagent multi-agent platform needs persistent chat/session storage. Requirements:

- High write throughput (streaming agent responses)
- TTL support for automatic data retention/expiration
- Simple key-value access pattern (session_id → messages)
- DynamoDB-compatible API (portable to AWS DynamoDB in production)
- Proven at scale for chat workloads

## Decision

Deploy **ScyllaDB** with **Alternator** (DynamoDB-compatible API) enabled on port 8000. Use the ScyllaDB Operator for lifecycle management.

```yaml
alternator:
  enabled: true
  writeIsolation: only_rmw_uses_lwt
```

Access pattern: Applications use the DynamoDB SDK/API against `scylla.local` (Alternator endpoint). No CQL knowledge required.

## Options Considered

1. **PostgreSQL (existing cluster)** — Already deployed. Pros: no new infrastructure. Cons: relational model awkward for append-only chat logs, no native TTL, connection pooling pressure from high-frequency writes, schema migrations for chat formats.

2. **Redis** — Already deployed. Pros: fast, in-memory. Cons: persistence not designed for long-term storage, memory-bound (expensive for growing chat history), eviction policies could lose data.

3. **MongoDB** — Document store, natural fit for chat. Cons: another operator to manage, another database to learn, no DynamoDB portability.

4. **ScyllaDB + Alternator** (chosen) — DynamoDB API on a disk-backed, high-performance NoSQL engine. Discord-proven at trillion+ message scale. Native TTL. Portable to real DynamoDB.

5. **AWS DynamoDB (real)** — Production-ready but requires AWS account, costs money for dev, latency from local cluster to cloud.

## Consequences

### Positive

- **DynamoDB API portability**: Same application code works against real DynamoDB in production
- **Native TTL**: Automatic data expiration without cron jobs or manual cleanup
- **Proven for chat**: Discord serves trillions of messages on ScyllaDB
- **Append-optimized**: LSM-tree storage ideal for write-heavy chat workloads
- **No schema migrations**: Schema-free document model for evolving chat formats
- **Operator-managed**: ScyllaDB Operator handles scaling, repair, backup

### Negative

- Additional infrastructure (operator + cluster + ~2Gi RAM in dev)
- Another database to monitor and maintain
- Alternator has subtle DynamoDB compatibility gaps (edge cases in transactions)
- `developerMode: true` required for Kind cluster (relaxed I/O requirements)
- ScyllaDB Operator is resource-heavy for a dev environment

### Write Isolation

`only_rmw_uses_lwt` — lightweight transactions only for read-modify-write operations. Pure writes are fast (no Paxos). Acceptable trade-off for chat where last-write-wins is fine.
