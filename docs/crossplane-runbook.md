# Crossplane Operations Runbook

## Quick Reference

### Health Checks

```bash
# Check all Crossplane components
kubectl get all -n crossplane-system

# Check provider health
kubectl get providers

# Check compositions
kubectl get compositions

# Check managed resources
kubectl get managed
```

### Common Commands

| Action               | Command                                                                     |
| -------------------- | --------------------------------------------------------------------------- |
| View Crossplane logs | `kubectl logs -n crossplane-system deployment/crossplane`                   |
| View provider logs   | `kubectl logs -n crossplane-system deployment/provider-aws-s3`              |
| Check secret sync    | `kubectl get externalsecrets -n crossplane-system`                          |
| Force reconciliation | `kubectl annotate bucket my-bucket crossplane.io/reconcile-now=$(date +%s)` |
| Pause resource       | `kubectl annotate bucket my-bucket crossplane.io/paused=true`               |
| Resume resource      | `kubectl annotate bucket my-bucket crossplane.io/paused-`                   |

## Deployment Procedures

### Initial Deployment

1. **Initialize secrets**:

   ```bash
   make init-aws-secrets
   ```

2. **Deploy Crossplane**:

   ```bash
   flux reconcile kustomization infrastructure-operators --with-source
   ```

3. **Verify deployment**:
   ```bash
   kubectl wait --for=condition=Ready pod -l app=crossplane -n crossplane-system --timeout=5m
   kubectl get providers
   ```

### Upgrading Crossplane

1. **Update version in helmrelease.yaml**:

   ```yaml
   spec:
     chart:
       spec:
         version: "1.18.3" # New version
   ```

2. **Apply changes**:

   ```bash
   git add apps/base/crossplane/helmrelease.yaml
   git commit -m "chore: Upgrade Crossplane to v1.18.3"
   git push
   ```

3. **Monitor upgrade**:
   ```bash
   flux get helmrelease crossplane -n flux-system --watch
   kubectl get pods -n crossplane-system --watch
   ```

### Adding New Providers

1. **Create provider manifest**:

   ```yaml
   apiVersion: pkg.crossplane.io/v1
   kind: Provider
   metadata:
     name: provider-aws-rds
   spec:
     package: xpkg.upbound.io/upbound/provider-aws-rds:v1.16.0
   ```

2. **Add to kustomization**:

   ```bash
   echo "  - provider-aws-rds.yaml" >> apps/base/crossplane/kustomization.yaml
   ```

3. **Deploy and verify**:
   ```bash
   kubectl apply -f provider-aws-rds.yaml
   kubectl wait --for=condition=Healthy provider/provider-aws-rds --timeout=5m
   ```

## Troubleshooting Guide

### Issue: Provider Not Healthy

**Symptoms**:

- Provider shows `HEALTHY: False`
- Resources stuck in `Creating` state

**Diagnosis**:

```bash
# Check provider status
kubectl describe provider provider-aws-s3

# Check provider pod
kubectl get pods -n crossplane-system | grep provider-aws-s3
kubectl logs -n crossplane-system deployment/provider-aws-s3

# Check events
kubectl get events -n crossplane-system --sort-by='.lastTimestamp'
```

**Resolution**:

1. Check credentials:

   ```bash
   kubectl get secret aws-credentials -n crossplane-system -o yaml
   ```

2. Verify External Secrets sync:

   ```bash
   kubectl get externalsecret crossplane-aws-credentials -n crossplane-system
   ```

3. Restart provider:
   ```bash
   kubectl delete pod -l pkg.crossplane.io/provider=provider-aws-s3 -n crossplane-system
   ```

### Issue: Resources Not Creating

**Symptoms**:

- Resources show `READY: False`
- No AWS resources created

**Diagnosis**:

```bash
# Check resource details
kubectl describe bucket my-bucket

# Check composition (if using)
kubectl describe composition xbuckets.aws.storage.platform.io

# Check Crossplane logs
kubectl logs -n crossplane-system deployment/crossplane --tail=50
```

**Resolution**:

1. Check ProviderConfig:

   ```bash
   kubectl get providerconfig
   kubectl describe providerconfig default
   ```

2. Verify LocalStack connectivity (dev):

   ```bash
   kubectl exec -n crossplane-system deployment/crossplane -- curl -s http://localstack.localstack.svc.cluster.local:4566/_localstack/health
   ```

3. Force reconciliation:
   ```bash
   kubectl annotate bucket my-bucket crossplane.io/reconcile-now=$(date +%s)
   ```

### Issue: External Secrets Not Syncing

**Symptoms**:

- ExternalSecret shows `SecretSyncError`
- AWS credentials not available

**Diagnosis**:

```bash
# Check External Secret status
kubectl describe externalsecret crossplane-aws-credentials -n crossplane-system

# Check ClusterSecretStore
kubectl describe clustersecretstore cluster-secret-store

# Check LocalStack secrets
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id crossplane/aws
```

**Resolution**:

1. Re-initialize secrets:

   ```bash
   ./scripts/init-crossplane-secrets.sh
   ```

2. Restart External Secrets operator:

   ```bash
   kubectl rollout restart deployment/external-secrets -n external-secrets
   ```

3. Check LocalStack health:
   ```bash
   kubectl get pods -n localstack
   kubectl logs -n localstack deployment/localstack
   ```

### Issue: Composition Not Working

**Symptoms**:

- XR (Composite Resource) created but no resources
- Composition shows errors

**Diagnosis**:

```bash
# Check XRD
kubectl get xrd xbuckets.storage.platform.io
kubectl describe xrd xbuckets.storage.platform.io

# Check Composition
kubectl describe composition xbuckets.aws.storage.platform.io

# Check function logs
kubectl logs -n crossplane-system deployment/function-patch-and-transform
```

**Resolution**:

1. Validate composition syntax:

   ```bash
   kubectl apply -f composition.yaml --dry-run=client
   ```

2. Check function installation:

   ```bash
   kubectl get functions
   ```

3. Review composite resource:
   ```bash
   kubectl get xbucket -o yaml
   ```

## Maintenance Procedures

### Daily Checks

```bash
#!/bin/bash
# Daily health check script

echo "=== Crossplane Health Check ==="
echo "1. Provider Status:"
kubectl get providers

echo "2. Failed Resources:"
kubectl get managed -A | grep False

echo "3. Recent Errors:"
kubectl logs -n crossplane-system deployment/crossplane --since=1h | grep ERROR

echo "4. Secret Sync Status:"
kubectl get externalsecrets -A | grep -v SecretSynced
```

### Weekly Maintenance

1. **Review resource usage**:

   ```bash
   kubectl top pods -n crossplane-system
   ```

2. **Check for updates**:

   ```bash
   helm search repo crossplane/crossplane --versions | head -5
   ```

3. **Audit managed resources**:
   ```bash
   kubectl get managed -A -o custom-columns=KIND:.kind,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,SYNCED:.status.conditions[?(@.type=="Synced")].status
   ```

### Monthly Tasks

1. **Backup configurations**:

   ```bash
   # Backup all Crossplane resources
   kubectl get providers,providerconfigs,compositions,xrds -o yaml > crossplane-backup-$(date +%Y%m%d).yaml

   # Backup managed resources
   kubectl get managed -A -o yaml > managed-resources-$(date +%Y%m%d).yaml
   ```

2. **Review and rotate credentials**:

   ```bash
   # Update AWS credentials in LocalStack/AWS Secrets Manager
   # Then force External Secrets refresh
   kubectl annotate externalsecret crossplane-aws-credentials -n crossplane-system force-sync=$(date +%s)
   ```

3. **Performance review**:
   ```bash
   # Check reconciliation metrics
   kubectl exec -n crossplane-system deployment/crossplane -- curl -s localhost:8080/metrics | grep reconcile
   ```

## Emergency Procedures

### Complete Crossplane Restart

```bash
# 1. Pause all managed resources
kubectl get managed -A -o name | xargs -I {} kubectl annotate {} crossplane.io/paused=true

# 2. Restart Crossplane
kubectl rollout restart deployment/crossplane -n crossplane-system

# 3. Wait for ready
kubectl wait --for=condition=Available deployment/crossplane -n crossplane-system --timeout=5m

# 4. Restart providers
kubectl get providers -o name | xargs -I {} kubectl delete pods -n crossplane-system -l pkg.crossplane.io/provider={}

# 5. Resume resources
kubectl get managed -A -o name | xargs -I {} kubectl annotate {} crossplane.io/paused-
```

### Disaster Recovery

```bash
# 1. Backup current state
kubectl get all,providers,providerconfigs,compositions,xrds,managed -A -o yaml > disaster-backup-$(date +%Y%m%d-%H%M%S).yaml

# 2. Delete Crossplane (if needed)
flux suspend kustomization infrastructure-operators
kubectl delete namespace crossplane-system

# 3. Clean up CRDs
kubectl get crd -o name | grep crossplane | xargs kubectl delete

# 4. Reinstall
flux resume kustomization infrastructure-operators
flux reconcile kustomization infrastructure-operators --with-source

# 5. Restore configurations
kubectl apply -f disaster-backup-*.yaml
```

### Resource Stuck in Deleting

```bash
# 1. Check finalizers
kubectl get bucket my-bucket -o jsonpath='{.metadata.finalizers}'

# 2. Remove finalizers (CAUTION: may leave orphaned resources)
kubectl patch bucket my-bucket -p '{"metadata":{"finalizers":[]}}' --type=merge

# 3. Force delete
kubectl delete bucket my-bucket --force --grace-period=0
```

## Performance Tuning

### Crossplane Controller

```yaml
# Adjust in helmrelease.yaml
args:
  - --max-reconcile-rate=100 # Default: 10
  - --poll-interval=1m # Default: 1m
  - --sync-period=10m # Default: 10m
```

### Provider Performance

```yaml
# Provider controller config
apiVersion: pkg.crossplane.io/v1alpha1
kind: ControllerConfig
metadata:
  name: aws-config
spec:
  args:
    - --max-reconcile-rate=50
  resources:
    limits:
      cpu: 500m
      memory: 1Gi
```

## Monitoring Setup

### Prometheus Alerts

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: crossplane-alerts
  namespace: crossplane-system
spec:
  groups:
    - name: crossplane
      interval: 30s
      rules:
        - alert: CrossplaneDown
          expr: up{job="crossplane"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Crossplane is down"

        - alert: ProviderUnhealthy
          expr: crossplane_provider_healthy == 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Provider {{ $labels.provider }} is unhealthy"

        - alert: ReconciliationErrors
          expr: rate(controller_runtime_reconcile_errors_total[5m]) > 0.1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "High rate of reconciliation errors"
```

### Grafana Dashboard

Import dashboard IDs:

- 13485: Crossplane Metrics
- 14127: Provider Metrics
- 15398: Managed Resources

## Security Procedures

### Secret Rotation

```bash
#!/bin/bash
# Rotate AWS credentials

# 1. Generate new credentials
NEW_ACCESS_KEY="new-access-key"
NEW_SECRET_KEY="new-secret-key"

# 2. Update in LocalStack/AWS
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
  --secret-id crossplane/aws \
  --secret-string "{\"access_key_id\":\"$NEW_ACCESS_KEY\",\"secret_access_key\":\"$NEW_SECRET_KEY\"}"

# 3. Force External Secrets sync
kubectl annotate externalsecret crossplane-aws-credentials -n crossplane-system \
  force-sync=$(date +%s)

# 4. Verify new credentials
kubectl get secret aws-credentials -n crossplane-system -o jsonpath='{.data.credentials}' | base64 -d
```

### RBAC Audit

```bash
# Review Crossplane permissions
kubectl get clusterrole | grep crossplane
kubectl describe clusterrole crossplane

# Check service account bindings
kubectl get rolebindings,clusterrolebindings -A | grep crossplane
```

## Integration Points

### Flux CD

```bash
# Check Flux sync status
flux get kustomization infrastructure-operators

# Force reconciliation
flux reconcile kustomization infrastructure-operators --with-source

# Suspend/Resume
flux suspend kustomization infrastructure-operators
flux resume kustomization infrastructure-operators
```

### External Secrets

```bash
# Check secret stores
kubectl get secretstores,clustersecretstores

# View External Secrets
kubectl get externalsecrets -A

# Force refresh
kubectl annotate externalsecret crossplane-aws-credentials -n crossplane-system \
  refresh-now=$(date +%s)
```

### LocalStack (Development)

```bash
# Check LocalStack health
curl http://localhost:4566/_localstack/health

# List secrets
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets

# Create test bucket
aws --endpoint-url=http://localhost:4566 s3 mb s3://test-bucket
```

## Useful Scripts

### Resource Cleanup

```bash
#!/bin/bash
# cleanup-orphaned-resources.sh

echo "Finding orphaned resources..."

# Find resources without owner references
kubectl get managed -A -o json | jq -r '.items[] | select(.metadata.ownerReferences == null) | "\(.kind)/\(.metadata.namespace)/\(.metadata.name)"'

echo "Run 'kubectl delete' on any resources you want to remove"
```

### Backup Script

```bash
#!/bin/bash
# backup-crossplane.sh

BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

echo "Backing up Crossplane to $BACKUP_DIR..."

# Core components
kubectl get providers -o yaml > $BACKUP_DIR/providers.yaml
kubectl get providerconfigs -o yaml > $BACKUP_DIR/providerconfigs.yaml
kubectl get compositions -o yaml > $BACKUP_DIR/compositions.yaml
kubectl get xrds -o yaml > $BACKUP_DIR/xrds.yaml

# Managed resources
kubectl get managed -A -o yaml > $BACKUP_DIR/managed-resources.yaml

# Composite resources
kubectl get composite -A -o yaml > $BACKUP_DIR/composite-resources.yaml

echo "Backup complete!"
```
