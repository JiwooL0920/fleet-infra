# ADR-013: Argo CD Hub–Spoke for Application Workloads

**Status:** Accepted
**Date:** 2026-06

## Context

Platform services (ingress, databases, observability) are GitOps-managed on a primary Kind cluster via Flux. We also need a **separate** cluster where **application-level** manifests can iterate quickly without expanding the Flux dependency graph on the hub, while still enforcing Git as source of truth.

Industry practice for this split is common at scale: **platform GitOps** (often Flux or a single pipeline) installs shared infrastructure; **application GitOps** (often Argo CD) targets team- or environment-specific clusters with app-of-apps or directory sync, with clear RBAC and blast-radius isolation (CNCF GitOps Principles; Argo CD multi-cluster docs).

## Decision

1. **Hub cluster** (`dev-services-amer`): unchanged Flux bootstrap; add **Argo CD** as an additional controller installed by Flux (`apps/base/argocd`).
2. **Spoke cluster** (`dev-applications`): second Kind cluster (Terraform), **no Flux bootstrap**; receives only manifests Argo CD syncs from a dedicated repo.
3. **Application source repo** `argocd-applications`: branch alignment with fleet-infra — `develop` → `metadata/dev-applications/`, `main` → `metadata/prod-applications/`.
4. **Cluster registration**: spoke API is reachable from the hub over the shared Docker `kind` network (`https://dev-applications-control-plane:6443`). The spoke bearer token is **not** stored in Git: a one-time script writes it to LocalStack Secrets Manager; **External Secrets** on the hub materializes the Argo CD cluster `Secret` (same pattern as `make setup-github-secret`).

## Consequences

- **Positive**: App teams can PR the `argocd-applications` repo without touching fleet-infra for routine app changes; clear separation of platform vs application lifecycle.
- **Positive**: Spoke stays minimal (no LocalStack, no full observability stack required on the spoke for the first iteration).
- **Trade-off**: Two clusters consume more host RAM/CPU; Terraform provisions the second cluster with non-conflicting host ports (8081/8444).
- **Operational**: After creating the spoke, run `make register-app-cluster` once so Argo CD can authenticate to the spoke.

## References

- Flux + Argo CD coexistence patterns are widely used (platform vs apps separation).
- Argo CD cluster registration: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
