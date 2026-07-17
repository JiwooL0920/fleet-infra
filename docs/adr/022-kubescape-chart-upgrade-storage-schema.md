# ADR-022: Upgrade Kubescape Chart 1.30.4 → 1.30.7 to Fix Broken Storage OpenAPI Schema

**Status:** Accepted
**Date:** 2026-07

## Context

[ADR-021](021-argocd-exclude-kubescape-softwarecomposition.md) attempted to unblock Argo CD reconciliation on the `dev-services-amer` hub by adding `resource.exclusions` for the `spdx.softwarecomposition.kubescape.io` API group. That change was applied cleanly by Flux but did not unblock sync — every Application still reported `Sync=Unknown, ComparisonError: failed to load open api schema`.

Deeper investigation confirmed why:

1. Kubescape's `storage` component (image `quay.io/kubescape/storage:v0.0.239`, restarted 289 times) publishes an aggregated APIService at `v1beta1.spdx.softwarecomposition.kubescape.io`.
2. `kubectl get --raw /openapi/v3/apis/spdx.softwarecomposition.kubescape.io/v1beta1` returns a document with **645 dangling `$ref` pointers** to schemas that don't exist (e.g. `ApplicationProfileList`, `ApplicationProfileSpec`, …). The document is fundamentally malformed.
3. Argo CD's application-controller warms a per-cluster cache using `client-go`'s OpenAPI schema loader, which fetches the aggregated document and fails on the first bad ref, aborting cache load for the whole cluster.
4. `resource.exclusions` filters what Argo CD *manages* after discovery — it does not opt out of the OpenAPI fetch itself, so it cannot fix this.

The `kubescape-operator` chart releases bundle a matching `storage` image. Comparing versions available on the upstream Helm repo:

| Chart version | Storage image |
|---|---|
| 1.30.4 (current) | `v0.0.239` (broken schema) |
| 1.30.7 (patch)   | `v0.0.272` |
| 1.40.2 (latest)  | `v0.0.274` |

`values.yaml` diff between 1.30.4 and 1.30.7 shows **zero removed keys** — only additive new options (`riskAcceptance`, `priorityClassName` on subcomponents, `sbomScanner`). Safe patch upgrade.

## Decision

Bump `KUBESCAPE_CHART_VERSION` in `base/services/environment.env` from `1.30.4` to `1.30.7`. Flux's `argocd-cluster-config` `HelmRelease` uses this as a substitution variable, so Flux rolls the upgrade out on the next reconcile.

The `resource.exclusions` block added by ADR-021 is retained: it is harmless and keeps Argo CD from ever tracking kubescape's scan-result CRs (which are runtime data, not GitOps state).

We stay on the 1.30.x line rather than jumping straight to 1.40.2 to minimize risk of unrelated chart-level breaking changes on the hub cluster.

## Consequences

- **Positive**: Rolls kubescape storage forward 33 image releases. Expected to ship a valid OpenAPI schema, unblocking Argo CD reconciliation for the hub cluster.
- **Positive**: Unblocks ADR-013 (hub–spoke) end-to-end for real. Applications sourced from `argocd-applications` and helm charts from `helm-charts` can finally sync.
- **Trade-off**: Kubescape storage pod restarts during upgrade (short scan-persistence outage; acceptable for a dev cluster).
- **Follow-up**: If 1.30.7 still ships a broken schema, escalate to 1.40.2 (bigger jump, requires closer values review).

## References

- Upstream chart repo: <https://kubescape.github.io/helm-charts/>
- Storage image registry: <https://quay.io/repository/kubescape/storage?tab=tags>
- Argo CD `client-go` OpenAPI cache path: `gitops-engine/pkg/cache/cluster.go` (`loadOpenAPISchema`)
- ADR-021 — the ineffective first attempt this ADR supersedes.
