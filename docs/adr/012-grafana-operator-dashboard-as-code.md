# ADR-012: Grafana Operator for Dashboard-as-Code

**Status:** Accepted
**Date:** 2026 (implemented), 2026-06 (documented as ADR)

## Context

Grafana dashboards need to be:
- Version-controlled (reproducible across cluster rebuilds)
- Declarative (GitOps-managed, not manually created in UI)
- Automatically provisioned on fresh cluster startup
- Consistent between dev and production environments

Traditional approaches (ConfigMap provisioning, Grafana provisioning API) have limitations around lifecycle management, updates, and multi-namespace support.

## Decision

Deploy **Grafana Operator** v5.15.x to manage dashboards, datasources, and folders via Kubernetes CRDs.

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: kubernetes-overview
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  json: |
    { ... dashboard JSON ... }
```

Configuration: `namespaceScope: false` — watches all namespaces for Grafana CRDs.

## Options Considered

1. **ConfigMap-based provisioning** — Mount dashboard JSON as ConfigMaps into Grafana pod. Pros: simple, no extra operator. Cons: requires Grafana restart for updates, ConfigMap size limits (1MB), no lifecycle management, awkward multi-file handling.

2. **Grafana provisioning directory** — File-based provisioning via sidecar. Similar to ConfigMap but with inotify-based reload. Cons: sidecar complexity, still requires ConfigMaps underneath.

3. **Grafana API + CI/CD** — Push dashboards via HTTP API in CI pipeline. Cons: not GitOps (imperative push), requires API token management, no reconciliation loop.

4. **Grafana Operator** (chosen) — CRD-based lifecycle management. Dashboards, datasources, folders as Kubernetes resources. Reconciliation loop ensures drift correction. Multi-namespace support.

5. **Grafonnet/Jsonnet** — Generate dashboard JSON programmatically. Complementary to any provisioning method (can combine with operator). Not a provisioning mechanism itself.

## Consequences

### Positive

- **Full GitOps**: Dashboards are Kubernetes manifests, managed by Flux like everything else
- **Drift correction**: Operator reconciles — manual UI edits get reverted to declared state
- **No restart required**: Dashboard updates apply without Grafana pod restart
- **Multi-namespace**: Dashboards can live alongside the services they monitor
- **Lifecycle management**: Delete the CRD → dashboard removed from Grafana
- **Folder support**: Organize dashboards into folders declaratively

### Negative

- Another operator to run (~128Mi RAM)
- CRD schema must match Grafana version (version coupling)
- Large dashboard JSONs are unwieldy in YAML (consider external references or Jsonnet generation)
- Operator watches all namespaces (potential RBAC concerns in multi-tenant clusters)
- Cannot easily "prototype in UI then export" workflow (operator reverts UI changes)

### Workflow

1. Create/edit dashboard JSON (manually or via Grafonnet)
2. Wrap in `GrafanaDashboard` CRD manifest
3. Commit to Git → Flux deploys → Operator provisions in Grafana
4. Operator continuously reconciles (drift protection)
