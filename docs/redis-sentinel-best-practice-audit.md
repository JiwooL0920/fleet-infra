# Redis Sentinel — Best Practice Evaluation Report

**Service:** Redis Sentinel (Bitnami Redis Helm Chart v20.7.0)
**Scope:** `apps/base/redis-sentinel/`, `base/services/redis-sentinel.yaml`, `base/services/redisinsight.yaml`, env configs
**Project context:** Personal/local dev infrastructure on Colima + Kind, with dev/prod GitOps environments via Flux CD
**Date:** 2026-03-12

---

## Executive Summary

The Redis Sentinel deployment is **well-structured for a personal infrastructure project** — environment-specific configuration via `postBuild` substitution, fine-grained Flux dependency management, proper persistence with RDB snapshots, resource limits on all components, and sensible pod anti-affinity for single-node clusters.

However, the audit found **2 correctness bugs that are likely causing Flux reconciliation failures right now**, plus several best-practice deviations worth addressing before promoting to production or scaling beyond local dev.

### Scorecard

| Category | Rating | Notes |
|---|---|---|
| **Correctness** | ⚠️ Needs Fix | Health check names don't match Bitnami chart output; ExternalSecret not deployed |
| **Security** | ✅ Acceptable (dev) | Auth disabled intentionally (documented Loki limitation); fine for local dev |
| **Resiliency** | ✅ Good | Sentinel HA, persistence, resource limits all configured |
| **Modularity** | ✅ Good | Clean base/dev/prod separation, env-var driven config |
| **Scalability** | ✅ Good | Replica counts and resources scale between environments |
| **Monitoring** | ⚠️ Partial | Metrics enabled in prod only; no dev observability |
| **Performance** | ✅ Good | LRU eviction, tuned memory, RDB-only persistence |
| **Project Structure** | ✅ Good | Fine-grained dependencies, clear ownership |

---

## Findings

### 🔴 CRITICAL — Actively Broken

---

#### F1. Flux Health Check References Non-Existent StatefulSets

| | |
|---|---|
| **Category** | Correctness |
| **Severity** | 🔴 Critical |
| **File** | `base/services/redis-sentinel.yaml` (lines 24-31) |
| **Impact** | Flux Kustomization may never reach `Ready` state; downstream `redisinsight` blocked by `dependsOn` |

**Current pattern:**
```yaml
# base/services/redis-sentinel.yaml
healthChecks:
  - apiVersion: apps/v1
    kind: StatefulSet
    name: redis-sentinel-master      # ❌ Does not exist
    namespace: redis-sentinel
  - apiVersion: apps/v1
    kind: StatefulSet
    name: redis-sentinel-replicas    # ❌ Does not exist
    namespace: redis-sentinel
```

**Problem:** The Bitnami Redis chart with `sentinel.enabled: true` and `fullnameOverride: redis-sentinel` creates a **single** StatefulSet named `redis-sentinel-node` — not separate `master` and `replicas` StatefulSets. The separate naming is only used when `architecture: replication` without Sentinel.

**Evidence:** `base/services/redisinsight.yaml` (line 26) correctly references `redis-sentinel-node`:
```yaml
# base/services/redisinsight.yaml — correct name
healthChecks:
  - apiVersion: apps/v1
    kind: StatefulSet
    name: redis-sentinel-node    # ✅ Correct Bitnami Sentinel name
    namespace: redis-sentinel
```

**Recommended pattern:**
```yaml
healthChecks:
  - apiVersion: apps/v1
    kind: StatefulSet
    name: redis-sentinel-node
    namespace: redis-sentinel
  - apiVersion: v1
    kind: Secret
    name: redis-password
    namespace: redis-sentinel
```

**Source:** [Bitnami Redis chart templates](https://github.com/bitnami/charts/tree/main/bitnami/redis/templates) — sentinel mode creates `redis-node` StatefulSet, not separate master/replica StatefulSets.

**Fix effort:** 🟢 5 minutes — change 2 lines in `base/services/redis-sentinel.yaml`

---

#### F2. ExternalSecret Not Deployed (Dead Code + Failed Health Check)

| | |
|---|---|
| **Category** | Correctness |
| **Severity** | 🔴 Critical |
| **File** | `apps/base/redis-sentinel/kustomization.yaml` |
| **Impact** | `redis-password` Secret never created; Flux health check for this Secret fails |

**Current pattern:**
```yaml
# apps/base/redis-sentinel/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrelease.yaml
  # externalsecret.yaml EXISTS in directory but is NOT listed here
```

**Problem:** `externalsecret.yaml` exists in `apps/base/redis-sentinel/` but is not included in the kustomization resources. This means:
1. The `ExternalSecret` is never applied to the cluster
2. The `redis-password` Kubernetes Secret is never created by External Secrets Operator
3. The health check in `base/services/redis-sentinel.yaml` (line 32-34) waits for `Secret/redis-password` which doesn't exist
4. This compounds with F1 — the Flux Kustomization has multiple failing health checks

**Note:** Since `auth.enabled: false`, Redis itself works without the secret. The issue is that Flux thinks the service isn't healthy.

**Recommended pattern — Option A (enable ExternalSecret):**
```yaml
resources:
  - namespace.yaml
  - helmrelease.yaml
  - externalsecret.yaml
```

**Recommended pattern — Option B (remove dead health check):**
If auth will remain disabled, remove the Secret health check from `base/services/redis-sentinel.yaml`:
```yaml
healthChecks:
  - apiVersion: apps/v1
    kind: StatefulSet
    name: redis-sentinel-node
    namespace: redis-sentinel
```

**Fix effort:** 🟢 5 minutes — either add 1 line to kustomization.yaml or remove 3 lines from redis-sentinel.yaml

---

### 🟡 MEDIUM — Should Address

---

#### F3. Image Tags Set to `latest` (Non-Reproducible Deployments)

| | |
|---|---|
| **Category** | Reliability / GitOps |
| **Severity** | 🟡 Medium |
| **Files** | `apps/base/redis-sentinel/helmrelease.yaml` (lines 36, 71), `apps/base/redisinsight/deployment.yaml` (line 20) |
| **Impact** | Deployments are non-deterministic; pod restarts may pull different versions silently |

**Current pattern:**
```yaml
image:
  tag: latest    # Redis
sentinel:
  image:
    tag: latest  # Sentinel
---
image: redis/redisinsight:latest  # RedisInsight
```

**Problem:** In GitOps, `latest` breaks the core principle that Git is the source of truth for what's deployed. Two reconciliation runs on the same commit can produce different cluster states. If a new `latest` image introduces a breaking change, there's no way to identify what changed or roll back to a specific version.

**Recommended pattern:**
```yaml
image:
  tag: "7.4.2"  # Pin to specific version
sentinel:
  image:
    tag: "7.4.2"
```

Use Flux's [Image Automation](https://fluxcd.io/flux/guides/image-update/) to automate version bumps via PRs while maintaining pinned tags in Git.

**Source:** [Kubernetes docs — Container Images](https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy): "You should avoid using the `:latest` tag, see Best Practices for Configuration."

**Fix effort:** 🟢 10 minutes — pin 3 image tags to current versions

---

#### F4. Deprecated Flux CD API Versions

| | |
|---|---|
| **Category** | Correctness / Maintenance |
| **Severity** | 🟡 Medium |
| **Files** | `apps/base/redis-sentinel/helmrelease.yaml` (lines 2, 12) |
| **Impact** | Will break on Flux CD upgrade; only redis-sentinel and loki still use beta APIs |

**Current pattern:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2   # ❌ Beta — deprecated
kind: HelmRepository
---
apiVersion: helm.toolkit.fluxcd.io/v2beta2      # ❌ Beta — deprecated
kind: HelmRelease
```

**Problem:** All other 18 services in this repo already use GA versions (`v1` / `v2`). Only `redis-sentinel` and `loki` remain on beta APIs. Flux CD will eventually remove beta API support — these manifests will stop reconciling.

**Recommended pattern:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1         # ✅ GA
kind: HelmRepository
---
apiVersion: helm.toolkit.fluxcd.io/v2            # ✅ GA
kind: HelmRelease
```

**Source:** [Flux CD HelmRelease API reference](https://fluxcd.io/flux/components/helm/helmreleases/) — GA `v2` is the current API.

**Fix effort:** 🟢 5 minutes — update 2 apiVersion strings

---

#### F5. Authentication Disabled Despite Secret Infrastructure

| | |
|---|---|
| **Category** | Security |
| **Severity** | 🟡 Medium (dev) / 🔴 High (prod) |
| **Files** | `apps/base/redis-sentinel/helmrelease.yaml` (line 43) |
| **Impact** | Any pod in the cluster can read/write/flush Redis without credentials |

**Current pattern:**
```yaml
auth:
  enabled: false
```

Meanwhile, the full auth infrastructure exists:
- `externalsecret.yaml` — maps `redis/credentials/password` from LocalStack
- LocalStack init hook creates `redis/credentials/password` in Secrets Manager
- Loki's `externalsecret.yaml` also references the same password

**Context:** The `docs/loki-redis-sentinel-limitation.md` documents that auth was disabled because Loki's Redis client doesn't properly support Sentinel + AUTH together. This is a known, investigated, intentional trade-off.

**Recommended approach:**
1. **Short term:** Keep auth disabled for local dev if Loki needs Redis. Document this prominently.
2. **For production:** Enable auth (`auth.enabled: true`, `auth.existingSecret: redis-password`). If Loki still can't handle Sentinel + AUTH, give Loki its own unauthenticated Redis instance.

**Source:** [Redis Security docs](https://redis.io/docs/latest/operate/oss_and_stack/management/security/): "Redis is designed to be accessed by trusted clients inside trusted environments. Access to the Redis port should be denied to everybody but trusted clients."

**Fix effort:** 🟡 30 minutes — enable auth + wire secret + verify Loki compatibility

---

#### F6. `stop-writes-on-bgsave-error no` Silences Persistence Failures

| | |
|---|---|
| **Category** | Data Integrity |
| **Severity** | 🟡 Medium |
| **File** | `apps/base/redis-sentinel/helmrelease.yaml` (line 50) |
| **Impact** | RDB snapshot failures go unnoticed; data loss window extends silently |

**Current pattern:**
```
stop-writes-on-bgsave-error no
```

**Problem:** When this is set to `no`, Redis continues accepting writes even if the background save process fails (e.g., disk full, permission error). This means the most recent RDB snapshot could be hours old (save interval is `10800 1` = 3 hours) and you'd have no indication of failure — the data since the last successful save is at risk.

**Context:** For a pure cache with LRU eviction, this is defensible — all data is reconstructable. But if any non-cache data ends up in Redis (sessions, queues, rate limits), silent persistence failure becomes a real risk.

**Recommended pattern:**
```
stop-writes-on-bgsave-error yes  # Default — stop accepting writes on save failure
```

Or keep `no` but add alerting on `rdb_last_bgsave_status` metric (requires metrics enabled).

**Source:** [Redis persistence docs](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/): "By default Redis will stop accepting writes if RDB snapshots are enabled and the latest background save failed."

**Fix effort:** 🟢 5 minutes — change to `yes`, or add Prometheus alert rule

---

### 🟢 LOW — Nice to Have

---

#### F7. No Metrics in Development Environment

| | |
|---|---|
| **Category** | Monitoring |
| **Severity** | 🟢 Low |
| **File** | `base/services/environment.env` (line 107), `clusters/stages/dev/.../environment.env` (line 63) |

`REDIS_METRICS_ENABLED=false` in both base and dev. Metrics are enabled in prod. This means performance issues and memory problems in dev won't be visible in Grafana until they hit prod.

**Recommended:** Enable metrics in dev. The overhead of the Redis exporter sidecar is minimal (~10MB RAM, negligible CPU).

**Fix effort:** 🟢 2 minutes — change `REDIS_METRICS_ENABLED=true` in dev environment.env

---

#### F8. No PodDisruptionBudgets

| | |
|---|---|
| **Category** | Resiliency |
| **Severity** | 🟢 Low (dev) / 🟡 Medium (prod) |
| **File** | Not configured anywhere |

No PDBs configured for Redis. In local dev on a single Kind node, this doesn't matter. For production with multiple nodes, a PDB prevents `kubectl drain` from evicting all Redis pods simultaneously.

**Recommended pattern (for prod):**
```yaml
# In helmrelease.yaml values
master:
  podDisruptionBudget:
    create: true
    minAvailable: 1
replica:
  podDisruptionBudget:
    create: true
    minAvailable: 1
```

**Source:** [Kubernetes PDB docs](https://kubernetes.io/docs/tasks/run-application/configure-pdb/): "A PDB limits the number of Pods of a replicated application that are down simultaneously from voluntary disruptions."

**Fix effort:** 🟢 5 minutes — add PDB values to helmrelease.yaml

---

#### F9. No NetworkPolicies for Redis Namespace

| | |
|---|---|
| **Category** | Security |
| **Severity** | 🟢 Low (dev) / 🟡 Medium (prod) |
| **File** | Not configured anywhere for redis-sentinel namespace |

Any pod in the cluster can connect to Redis on port 6379. Combined with `auth.enabled: false`, this means zero access control. For local dev this is fine; for shared or production clusters, NetworkPolicies should restrict access to known consumers.

**Fix effort:** 🟡 20 minutes — create NetworkPolicy allowing traffic only from known namespaces (n8n, loki, temporal, etc.)

---

#### F10. No `tcp-keepalive` or `timeout` in Redis Configuration

| | |
|---|---|
| **Category** | Performance |
| **Severity** | 🟢 Low |
| **File** | `apps/base/redis-sentinel/helmrelease.yaml` (commonConfiguration block) |

No connection management settings configured. Redis defaults (`tcp-keepalive 300`, `timeout 0`) are generally reasonable, but for long-lived Kubernetes connections through Sentinel proxies, explicit keepalive helps detect broken connections faster.

**Recommended addition to commonConfiguration:**
```
tcp-keepalive 60
timeout 300
```

**Source:** [Redis configuration docs](https://redis.io/docs/latest/operate/oss_and_stack/management/config/): `tcp-keepalive` — "If non-zero, use SO_KEEPALIVE to send TCP ACKs to clients in absence of communication."

**Fix effort:** 🟢 2 minutes — add 2 lines to commonConfiguration

---

### ℹ️ INFO — Awareness Only

---

#### F11. `external-secrets.io/v1beta1` API Version

All ExternalSecrets in the repo use `v1beta1`. The GA `v1` API has been available since ESO v0.9.0+. This is a **repo-wide pattern**, not Redis-specific. **⚠️ Breaking change:** ESO v0.17.0+ (May 2025) [dropped v1beta1 support entirely](https://github.com/external-secrets/external-secrets/issues/4785) — upgrading ESO without updating manifests will break all ExternalSecrets. Plan a repo-wide migration to `v1` before any ESO upgrade.

#### F12. `masterService.enabled: false`

Documented and intentional. Clients should use Sentinel-aware connections. This avoids the kubectl sidecar dependency the Bitnami chart requires for master tracking. Correct for Sentinel-aware clients.

#### F13. `rbac.create: false`

Appropriate for Kind clusters where RBAC is often permissive. For production, consider `rbac.create: true` to create proper ServiceAccount and RBAC bindings.

#### F14. `appendonly no`

Documented and intentional. For a cache workload with LRU eviction, AOF is unnecessary overhead. RDB snapshots every 3 hours provide crash recovery for non-volatile data patterns. If Redis use expands beyond caching, revisit this.

#### F15. RedisInsight Uses `image: latest`

Same concern as F3 but for the management UI. Lower impact since it's a dev tool, not a data path. Pin when convenient.

---

## What's Done Well

1. **Environment-specific configuration** — Clean base/dev/prod separation using Flux `postBuild.substituteFrom` with ConfigMaps. Resource limits, replica counts, and storage sizes all scale appropriately between environments.

2. **Fine-grained Flux dependency management** — `redis-sentinel` depends only on `external-secrets-config`; `redisinsight` depends only on `redis-sentinel`. No over-broad wave dependencies.

3. **Resource limits on every component** — Master, replicas, and sentinels all have explicit `requests` and `limits`. No unbounded resource consumption.

4. **Proper persistence strategy** — RDB with compression and checksums. Storage class persistence enabled with environment-appropriate sizing (8Gi dev, 16Gi prod).

5. **Memory management** — `maxmemory` with `allkeys-lru` eviction. Memory limits aligned with Redis maxmemory to prevent OOM kills.

6. **Pod anti-affinity** — `soft` anti-affinity is the right choice for single-node Kind clusters. Would need `hard` for multi-node prod.

7. **Comprehensive documentation** — README with connection examples, migration docs, Loki limitation investigation. Decisions are traceable.

8. **Sentinel tuning via env vars** — `downAfterMilliseconds`, `failoverTimeout`, and `parallelSyncs` are configurable per environment.

---

## Priority Action Items

| Priority | Finding | Effort | Impact |
|---|---|---|---|
| **P0 — Fix now** | F1: Health check StatefulSet names | 5 min | Flux reconciliation correctness |
| **P0 — Fix now** | F2: ExternalSecret not deployed / health check | 5 min | Flux reconciliation correctness |
| **P1 — Soon** | F4: Deprecated Flux API versions | 5 min | Prevent breakage on Flux upgrade |
| **P1 — Soon** | F3: Pin image tags | 10 min | Reproducible deployments |
| **P2 — When convenient** | F5: Enable auth for prod | 30 min | Security posture for production |
| **P2 — When convenient** | F6: Re-enable stop-writes-on-bgsave-error | 5 min | Data integrity safety net |
| **P3 — Backlog** | F7: Enable dev metrics | 2 min | Dev observability |
| **P3 — Backlog** | F8-F10: PDBs, NetworkPolicies, keepalive | 30 min | Production hardening |

**Total estimated effort for P0+P1:** ~25 minutes

---

## References

- [Redis Sentinel Documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)
- [Redis Security](https://redis.io/docs/latest/operate/oss_and_stack/management/security/)
- [Redis Persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)
- [Redis Configuration](https://redis.io/docs/latest/operate/oss_and_stack/management/config/)
- [Bitnami Redis Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [Flux CD HelmRelease API](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Flux CD Source API](https://fluxcd.io/flux/components/source/helmrepositories/)
- [Kubernetes Container Images](https://kubernetes.io/docs/concepts/containers/images/)
- [Kubernetes PodDisruptionBudgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [External Secrets Operator](https://external-secrets.io/latest/)
