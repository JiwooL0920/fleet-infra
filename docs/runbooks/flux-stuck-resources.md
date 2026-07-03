# Flux Stuck Resources Runbook

Operational guide for when a Flux Kustomization or HelmRelease stays not-Ready for > 15 minutes.

## Symptoms

Key indicators of stuck Flux resources:

```bash
# Check non-Ready Kustomizations
flux get kustomizations -A | awk 'NR==1 || $5!="True"'

# Check failed HelmReleases
flux get helmreleases -A | awk 'NR==1 || $4!="True"'
```

Common symptoms:
- Kustomization or HelmRelease showing non-Ready status for > 15 minutes
- HelmRelease stuck in `pending-upgrade` state
- HelmRelease retry count > 10
- Downstream services not updating due to `dependsOn` cascade

## Impact

- **Dependency cascade**: Services with `dependsOn` will not reconcile, blocking entire chains
- **Configuration drift**: Cluster state diverges from Git
- **Deployment freeze**: New changes cannot roll out to dependent services
- **Manual intervention required**: Automatic remediation exhausted

## Immediate Diagnostics

```bash
# Get detailed status for a stuck Kustomization
kubectl describe kustomization <name> -n flux-system | tail -30

# Get detailed status for a stuck HelmRelease
kubectl describe helmrelease <name> -n flux-system | tail -30

# Check Helm release history (Flux stores secrets in flux-system namespace)
helm history <release-name> -n flux-system
helm get values <release-name> -n flux-system

# Check pod status and recent events
kubectl get pods -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Check Flux controller logs
kubectl logs -n flux-system deploy/helm-controller --tail=50
kubectl logs -n flux-system deploy/kustomize-controller --tail=50
```

## Common Causes

### 1. Chart Values Validation Failure

Helm charts may have coupled field requirements not obvious in documentation. **Example**: Bitnami charts requiring RBAC/ServiceAccount when certain features enabled.

**Solution**: Review chart values schema, check chart source, or disable problematic features.

### 2. Image Tag Deleted from Registry

Container images referenced by the chart may be deleted from the upstream registry.

**Real example (2026-07-02)**: Bitnami Redis chart 20.7.0 with `masterService.enabled: true` injected a `kubectl-shared` sidecar using `bitnami/kubectl:1.32.0-debian-12-r0`. This tag was deleted from Docker Hub during Bitnami's mid-2025 registry migration. Result: pod stuck at `2/3 ImagePullBackOff`, HelmRelease in 1189-retry loop for 3 weeks. Fixed by ADR-015 (disabled masterService).

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "ImagePullBackOff"
```

**Solution**: Update chart version, pin to alternative image, or disable feature requiring the missing image.

### 3. Helm Stuck in `pending-upgrade` State

Helm operations can timeout and leave release locked, preventing further upgrades.

**Diagnosis**: `helm history <release-name> -n flux-system` — look for `pending-upgrade` or `pending-install`

**Solution**: Force rollback to last successful revision (see Recovery Procedures).

### 4. Resource Quota or Limit Exceeded

**Diagnosis**: `kubectl describe pod <pod-name> -n <namespace>` — look for `FailedScheduling`, `Insufficient cpu/memory`

### 5. Git Source Out of Sync

**Diagnosis**: `flux get sources git` — check Last Update timestamp and Revision

## Recovery Procedures

### Force Git Reconciliation

```bash
# Force Flux to fetch latest from Git
flux reconcile source git flux-system

# Force Kustomization reconciliation
flux reconcile kustomization <name>

# Force HelmRelease reconciliation
flux reconcile helmrelease <name> -n flux-system
```

### Rollback Stuck HelmRelease

If a HelmRelease is stuck in `pending-upgrade`:

```bash
# 1. Suspend the HelmRelease to stop Flux from retrying
flux suspend helmrelease <name> -n flux-system

# 2. Manually rollback using Helm (replace <revision> with last successful revision from helm history)
helm rollback <release-name> <revision> -n flux-system --force --no-hooks

# Alternatively, rollback to first/last revision
helm rollback <release-name> 1 -n flux-system --force --no-hooks  # first revision
helm rollback <release-name> 0 -n flux-system --force --no-hooks  # last successful

# 3. Resume the HelmRelease
flux resume helmrelease <name> -n flux-system
```

### Force Delete Stuck Pods

```bash
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force
# StatefulSets/Deployments will recreate with updated spec
```

### WIP Stash Pattern

```bash
git stash push --keep-index -u -m "tmp-fix-<issue-description>"
# Make fix, commit, push
git stash pop
```

### Emergency: Disable Service Temporarily

```bash
# Comment out service in base/services/kustomization.yaml, commit, and push
git add base/services/kustomization.yaml
git commit -m "temp: disable <service-name> pending fix for <issue>"
git push origin develop
# Create ADR if architectural decision changed; create follow-up task to re-enable
```

## Postmortem Checklist

After resolving a stuck resource incident:

- [ ] **Root cause identified**: Document what caused the issue (chart bug, registry issue, config error, etc.)
- [ ] **Fix committed to Git**: Never apply fixes directly to cluster — commit to `develop` branch
- [ ] **ADR created if needed**: If an architectural decision changed (e.g., disabling a feature), create an ADR in `docs/adr/`
- [ ] **Failure remediation configured**: Set `spec.install.remediation.retries` and `spec.upgrade.remediation.retries` in the HelmRelease
- [ ] **Alert runbook updated**: If monitoring alert triggered this incident, update the `runbook_url` annotation
- [ ] **Dependency graph reviewed**: Check if any `dependsOn` chains need adjustment
- [ ] **Documentation updated**: Update `AGENTS.md` or relevant `docs/` files if new patterns discovered
- [ ] **Upstream issue filed**: If caused by chart bug or registry issue, file issue with upstream maintainer

## References

- **ADR-014**: Redis sentinel masterService chart validation requirements (Superseded)
- **ADR-015**: Disable Redis sentinel masterService
- **Flux HelmRelease Docs**: https://fluxcd.io/flux/components/helm/helmreleases/
- **Flux Failure Remediation**: https://fluxcd.io/flux/components/helm/helmreleases/#configuring-failure-remediation
- **Flux Troubleshooting**: https://fluxcd.io/flux/cheatsheets/troubleshooting/
- **Helm Rollback Docs**: https://helm.sh/docs/helm/helm_rollback/

## See Also

- `CLAUDE.md` — Full architecture reference and adding new services workflow
- `AGENTS.md` — GitOps principles and documentation discipline
- `docs/adr/` — Architecture Decision Records (append-only log)
