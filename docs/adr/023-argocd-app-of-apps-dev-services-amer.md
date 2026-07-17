# ADR-023: App-of-Apps Root Applications Replace the Orphaned `dev-applications` Bootstrap

**Status:** Accepted
**Date:** 2026-07

## Context

[ADR-013](013-argocd-hub-spoke-applications.md) established a hub–spoke model where Flux on the hub cluster bootstraps a single Argo CD `Application` (`dev-applications`) that syncs `metadata/dev-applications/` from the [`argocd-applications`](https://github.com/JiwooL0920/argocd-applications) repo into a separate `dev-applications` spoke Kind cluster.

Two things drifted since:

1. The `argocd-applications` repo was **restructured** away from the flat `metadata/{dev,prod}-applications/` layout onto a per-cluster layout (`clusters/<cluster>/<workspace>/`, `clusters-services/<cluster>/`, `metadata/<cluster>/<workspace>/`). The old `metadata/dev-applications/` path and the `develop` branch the root `Application` was tracking **no longer exist**, so the App has been stuck at `Sync=OutOfSync, Health=Missing` for a week.
2. The separate `dev-applications` spoke Kind cluster is not part of my current dev flow — everything is currently exercised on the hub cluster `dev-services-amer`. The distinction "workloads on spoke vs platform on hub" was aspirational; in practice both live on the hub for now.

Two new Argo CD Applications had been applied manually with `kubectl` to prove the restructured `argocd-applications` layout syncs end-to-end (see the working smoke test with a helm-chart-sourced release). These need to move under GitOps management.

## Decision

Retire the single `dev-applications` root Application and replace it with two smaller root Applications, keeping the same app-of-apps pattern but aligned with the new `argocd-applications` layout:

| Root Application | Source path in `argocd-applications` | Purpose |
|---|---|---|
| `dev-services-amer-workloads` | `metadata/dev-services-amer/` | Aggregates per-workspace child Applications (workload manifests under `clusters/`) |
| `dev-services-amer-platform`  | `clusters-services/dev-services-amer/` | Aggregates platform-component child Applications (Helm-chart-sourced, from the `helm-charts` repo) |

Both:

- Source repo: `argocd-applications`, branch `main` (matches current repo state; `develop` branch does not exist).
- `directory.recurse: true` — every YAML in the subtree that is an Argo CD `Application` becomes a child.
- `destination.server: https://kubernetes.default.svc` — the hub cluster is now both hub *and* target for these workloads. Reintroduce a `destination.name: <spoke>` override if/when a real spoke returns.
- `syncPolicy.automated.{prune, selfHeal} = true`, `syncOptions: [ServerSideApply=true]` — same defaults as the previous root.

The old registered spoke cluster `Secret` (`argocd/dev-applications`, provisioned by Terraform per ADR-018) is left in place — it is Terraform-owned and out of Flux's scope. If the spoke Kind cluster is being retired, delete that resource in `terraform-infra` as a separate change.

## Consequences

- **Positive**: Argo CD Applications for dev-services-amer are fully GitOps-managed via `fleet-infra`; no more `kubectl apply` drift. Deleting a root App drains its children; adding a manifest under the referenced path creates a new child on the next reconcile.
- **Positive**: Split root Applications keep workload lifecycle (frequent app changes) separate from platform lifecycle (cert-manager, ingress, monitoring, etc.). Independent sync/health status per concern.
- **Positive**: Old orphaned `dev-applications` App is pruned by Flux automatically on next reconcile (removed from `argocd-cluster-config` Kustomization inventory).
- **Trade-off**: The child Applications currently living under `argocd-applications` will be *adopted* by the root Apps on first reconcile — names and namespaces match, so Argo CD patches them in place. No workload downtime expected.
- **Trade-off**: Two extra Application objects on the hub cluster vs. the previous single root. Overhead is negligible.
- **Revisit when**: A real prod spoke or a second dev spoke cluster is added — then this pattern needs a `destination` override (or an ApplicationSet across a cluster list).

## References

- [ADR-013](013-argocd-hub-spoke-applications.md) — original hub–spoke decision this refines.
- [ADR-018](018-terraform-provisioned-argocd-cluster-secret.md) — explains the still-registered `dev-applications` cluster Secret.
- [ADR-022](022-kubescape-chart-upgrade-storage-schema.md) — the kubescape upgrade that unblocked Argo CD sync on the hub, without which this ADR would be pointless.
- Argo CD app-of-apps pattern: <https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/>
