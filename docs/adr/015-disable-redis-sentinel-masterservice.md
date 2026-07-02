# ADR-015: Disable Redis Sentinel `masterService` — Clients Use Standard Service

**Status:** Accepted
**Date:** 2026-07-02
**Supersedes:** ADR-014

## Context

ADR-014 (accepted a few hours earlier the same day) documented enabling
`sentinel.masterService.enabled: true` on the Bitnami redis chart to give
non-Sentinel-aware clients a stable ClusterIP that always points at the current master.
That required setting three coupled fields (`rbac.create`, `serviceAccount.create`,
`replica.automountServiceAccountToken`) to satisfy chart validation.

Applying that fix succeeded at the values layer, but the chart then injected a
`kubectl-shared` sidecar container into every replica pod using
`bitnami/kubectl:1.32.0-debian-12-r0`. Bitnami's mid-2025 Docker Hub migration removed
that tag from the free tier, so the pod stuck at `2/3 ImagePullBackOff` and the
HelmRelease never became Ready. There is no chart flag to keep the master service but
skip the sidecar — the two are coupled 1:1 in
`bitnami/redis/templates/sentinel/statefulset.yaml`.

Auditing actual consumers of the `redis-sentinel-master` service in this repo showed
only one reference: `apps/base/argocd/helmrelease.yaml` set
`externalRedis.host: redis-sentinel-master...`. No other workload (Loki, kagent, n8n,
temporal) uses it.

## Decision

Reverse ADR-014. Disable `sentinel.masterService.enabled` and drop the coupled fields:

```yaml
sentinel:
  masterService:
    enabled: false

replica:
  automountServiceAccountToken: false
```

The `serviceAccount:` block is removed entirely. `rbac.create: true` stays (harmless
and consistent with the chart's default annotations).

Point Argo CD's external Redis at the standard Sentinel ClusterIP service instead:

```yaml
externalRedis:
  host: redis-sentinel.redis-sentinel.svc.cluster.local
  port: 6379
```

That service already routes port 6379 to any redis pod in the statefulset. Argo CD's
Redis client retries on write-to-replica errors, which is acceptable behavior for a dev
cluster where failovers are rare and Argo CD's Redis usage is caching/queuing (no
data-loss-critical writes).

Also fix a latent bug in `base/services/redis-sentinel.yaml` — its `healthChecks`
referenced StatefulSets `redis-sentinel-master` and `redis-sentinel-replicas` that never
existed under `architecture: replication` with Sentinel enabled. The actual statefulset
is `redis-sentinel-node`.

## Consequences

### Positive

- HelmRelease upgrades cleanly with no reliance on the deleted Bitnami kubectl tag.
- Removes the `kubectl-shared` sidecar (one fewer container per replica, no bound SA
  token exposure).
- Kustomization `healthChecks` now reference the real StatefulSet.
- One less coupling between our config and a chart-side sidecar controller.

### Negative

- If master fails over, Argo CD may briefly see writes routed to a replica and get
  `READONLY` errors until the ClusterIP endpoint updates (Sentinel triggers a rolling
  restart on failover, K8s Endpoints refresh in seconds). Acceptable for dev; would need
  revisiting if we host Argo CD in a HA-critical prod path.
- If a future workload needs a master-only stable endpoint, we'll have to either
  re-enable `masterService.enabled` (and re-solve the kubectl image problem) or use a
  Sentinel-aware Redis client.

## References

- ADR-014 (superseded): earlier same-day decision to keep masterService enabled.
- Bitnami chart template coupling:
  `bitnami/charts` → `bitnami/redis/templates/sentinel/statefulset.yaml` (`kubectl-shared`
  container is gated on `sentinel.masterService.enabled OR sentinel.service.createMaster`).
- ADR-002: Loki Redis usage — unaffected (Loki does not currently enable Redis caching
  in its live config, and the `redis-master` service ADR-002 mentioned came from a
  different chart flag that we do not set).
- ADR-013: Argo CD hub-spoke — the external Redis endpoint claim needs the update in
  this ADR applied.
