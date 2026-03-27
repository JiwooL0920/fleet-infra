# Grafana Operator

Kubernetes operator for declarative Grafana dashboard management using CRDs.

## Purpose

- Manage Grafana dashboards as Kubernetes resources (GrafanaDashboard CR)
- Organize dashboards into folders (GrafanaFolder CR)
- GitOps-friendly dashboard deployment
- Automatic sync with Grafana instances

## CRDs Provided

- `Grafana` - Grafana instance configuration
- `GrafanaFolder` - Dashboard folders
- `GrafanaDashboard` - Dashboard definitions (JSON or reference)
- `GrafanaDatasource` - Datasource configurations
- `GrafanaAlertRuleGroup` - Alert rule groups

## Usage Pattern

```yaml
# Create a folder
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaFolder
metadata:
  name: my-service
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"

# Create a dashboard
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: my-dashboard
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  folder: "my-service"
  json: |
    { ... dashboard JSON ... }
```

## Dependencies

- **Depends on**: kube-prometheus-stack (Grafana instance)
- **Depended on by**: Application dashboards

## References

- [Grafana Operator Docs](https://grafana.github.io/grafana-operator/)
- [GitHub Repository](https://github.com/grafana/grafana-operator)
