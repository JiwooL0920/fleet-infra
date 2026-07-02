# ADR-014: Redis Sentinel `masterService` Chart Validation Requirements

**Status:** Accepted
**Date:** 2026-07-02

## Context

ADR-002 and ADR-013 both depend on the Bitnami `redis` chart's Sentinel-tracked master
service (`redis-sentinel-master` / `sentinel.masterService.enabled: true`) so that
non-Sentinel-aware clients (Loki, Argo CD) get a stable ClusterIP that always points at the
current master.

Starting in Bitnami `redis` chart v20.x, enabling this feature triggers a values-validation
template (`redis.validateValues.createMaster` in `redis/templates/_helpers.tpl`) that
requires **three coupled fields** to all be true:

```go-template
{{- if and (or .Values.sentinel.masterService.enabled .Values.sentinel.service.createMaster)
          (or (not .Values.rbac.create)
              (not .Values.replica.automountServiceAccountToken)
              (not .Values.serviceAccount.create)) }}
```

We had `rbac.create: true` but were missing the other two. This produced a hard Helm
upgrade failure on every reconcile:

```
redis: sentinel.masterService.enabled
  In order to redirect requests only to the master pod via the service, you also need to
  create rbac and serviceAccount. In addition, you need to enable
  replica.automountServiceAccountToken.
```

Running pods were unaffected (upgrade-path breakage only), but Flux was stuck in a
1,189-retry loop over ~3 weeks. This cascaded via `dependsOn` to `argocd`,
`argocd-cluster-config`, and `redisinsight` kustomizations.

**Why the coupling exists:** the master service uses a label selector to route traffic to
the current master pod. To keep the label accurate across failovers, a Kubernetes controller
(shipped as part of the chart) relabels pods as master/replica based on Sentinel state. That
controller runs as a sidecar inside each replica pod and needs a bound ServiceAccount token
to call the Kubernetes API — hence RBAC + ServiceAccount + `automountServiceAccountToken`.

## Decision

Keep `sentinel.masterService.enabled: true` (required by ADR-002 and ADR-013) and set the
three coupled fields as a **contract**:

```yaml
rbac:
  create: true

serviceAccount:
  create: true

replica:
  automountServiceAccountToken: true
```

Inline comments in [apps/base/redis-sentinel/helmrelease.yaml](../../apps/base/redis-sentinel/helmrelease.yaml)
document the coupling at each field so a future engineer editing values does not delete any
of them as "unused".

## Consequences

### Positive

- Helm upgrades succeed; Argo CD and Redisinsight unblocked via `dependsOn`.
- Master service label controller can now relabel pods correctly during failover, matching
  the assumption ADR-002 and ADR-013 rely on.
- Coupling is documented both at the code site (inline comments) and here (rationale).

### Negative

- Replicas now mount a real ServiceAccount token, slightly increasing blast radius if a
  replica pod is compromised. The bound SA has only the minimal RBAC created by the chart
  (patch labels on redis pods), so the practical exposure is small.
- Future chart version bumps must re-verify this validator has not gained additional
  required fields.

## References

- Bitnami chart validator source: `bitnami/charts` → `bitnami/redis/templates/_helpers.tpl`
  (`redis.validateValues.createMaster`)
- ADR-002: Loki Redis Direct Connection (Bypassing Sentinel)
- ADR-013: Argo CD Hub–Spoke for Application Workloads
