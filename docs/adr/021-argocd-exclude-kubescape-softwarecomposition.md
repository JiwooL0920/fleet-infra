# ADR-021: Exclude Kubescape Aggregated APIService from Argo CD Discovery

**Status:** Accepted
**Date:** 2026-07

## Context

Argo CD Application controllers rebuild a per-cluster OpenAPI cache before every reconciliation so they can validate rendered manifests against the live API surface. On the hub cluster (`dev-services-amer`), this cache load began failing with:

```
error getting openapi resources: SchemaError(
  github.com/kubescape/storage/pkg/apis/softwarecomposition/v1beta1.ApplicationProfile.spec
): unknown model in reference: "…ApplicationProfileSpec"
```

The source is `v1beta1.spdx.softwarecomposition.kubescape.io`, an aggregated APIService served by `kubescape/storage`. Its published OpenAPI document contains a broken `$ref` to a model that the aggregation layer never exposes. One bad schema poisons the whole cluster cache: every Argo CD Application (both the hub-managed `dev-applications` App and any new ones from `argocd-applications`) is stuck at `sync=Unknown, condition=ComparisonError` and cannot deploy anything.

Kubescape itself keeps working — only Argo CD's discovery is affected — so uninstalling or downgrading kubescape is disproportionate.

## Decision

Add a cluster-wide `resource.exclusions` entry to the Argo CD Helm values (`apps/base/argocd/helmrelease.yaml`) that hides the broken API group from Argo CD's discovery:

```yaml
configs:
  cm:
    resource.exclusions: |
      - apiGroups:
          - spdx.softwarecomposition.kubescape.io
        kinds:
          - "*"
        clusters:
          - "*"
```

Argo CD then never enumerates that group's resources, its OpenAPI cache builds cleanly, and Applications reconcile normally.

## Consequences

- **Positive**: Every Argo CD Application on the hub can sync again. Unblocks ADR-013 (hub–spoke Applications) end-to-end.
- **Positive**: No change to kubescape itself; its scan results and controllers keep functioning.
- **Trade-off**: `spdx.softwarecomposition.kubescape.io/*` resources are invisible to Argo CD — acceptable because we never intended to manage them via GitOps (they are runtime scan output).
- **Revisit when**: kubescape upstream ships a fixed OpenAPI schema (tracked at [kubescape/storage#…](https://github.com/kubescape/storage/issues)), at which point the exclusion can be removed.

## References

- Argo CD `resource.exclusions` docs: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#resource-exclusioninclusion
- Related Argo CD issue on aggregated APIService schema failures: https://github.com/argoproj/argo-cd/issues/9944
- ADR-013 (Argo CD hub–spoke) — this ADR unblocks it in practice.
