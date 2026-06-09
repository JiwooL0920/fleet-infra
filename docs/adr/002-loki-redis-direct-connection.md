# ADR-002: Loki Redis Direct Connection (Bypassing Sentinel)

**Status:** Accepted
**Date:** 2025-08 (implemented), 2026-06 (documented as ADR)

## Context

Loki uses Redis for multi-layer caching (query results, chunks, index queries, write deduplication). Our Redis deploys with Bitnami Helm chart in replication + Sentinel mode for HA.

**Problem:** Loki's Redis client (go-redis) does **not** expose the `SentinelPassword` config parameter. The underlying go-redis library supports it (`FailoverOptions.SentinelPassword`), but Loki's wrapper struct omits it.

**Error:**
```
sentinel: GetMasterAddrByName master="mymaster" failed: NOAUTH Authentication required.
```

This means Loki cannot perform Sentinel discovery when Sentinel authentication is enabled — which it is by default in Bitnami's chart and cannot be reliably disabled via chart parameters.

**Upstream status:** Grafana Tempo solved this same issue (grafana/tempo#1463). Loki has not. No timeline for fix.

## Options Considered

1. **Disable Sentinel authentication** — Bitnami chart params (`auth.sentinel: false`, `sentinel.usePassword: false`) don't work reliably in v20.x. Security regression regardless.
2. **Direct Redis master connection** — Bypass Sentinel entirely using `redis-master` Kubernetes service.
3. **Wait for Loki fix** — Unknown timeline.
4. **Fork Loki** — Maintenance burden for a cache feature.

## Decision

Use **service segregation** with direct Redis connections:

- **Write-critical caches** (write deduplication) → `redis-master.redis-sentinel.svc.cluster.local:6379` (master-only for consistency)
- **Read-heavy caches** (results, chunks, index) → `redis-master.redis-sentinel.svc.cluster.local:6379` (same service, guaranteed writable)

Enable dedicated master service via Bitnami chart:
```yaml
sentinel:
  service:
    createMaster: true
```

This service auto-updates during failover — Sentinel still handles HA internally, clients just don't need to speak the Sentinel protocol.

## Consequences

### Positive

- Loki caching fully functional with all cache layers active
- Redis authentication remains enabled (no security regression)
- Automatic failover still works (Sentinel promotes replica, K8s service updates)
- No Loki fork or custom build required

### Negative

- Client doesn't participate in Sentinel discovery (relies on K8s service update latency)
- Brief cache unavailability during failover (seconds, not minutes)
- If Loki ever adds `SentinelPassword`, should revisit for proper Sentinel integration

## References

- Loki issue: grafana/loki#11564
- Tempo fix (same problem): grafana/tempo#1463
- Bitnami chart issue: bitnami/charts#3366
