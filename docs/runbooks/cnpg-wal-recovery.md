# CNPG PostgreSQL WAL Archive Recovery Failure

Operational runbook for recovering a CNPG PostgreSQL replica pod stuck in CrashLoopBackOff during WAL archive recovery.

## Symptoms

- Pod `postgresql-cluster-N` in CrashLoopBackOff with restart count > 100
- `kubectl logs` shows: `"Database cluster state: in archive recovery"` and `"PostgreSQL process exited with errors"`
- `kubectl get cluster postgresql-cluster -n cnpg-system` shows `phase: Failing over`, `readyInstances` < expected

## Impact

- `flux get kustomizations | grep postgresql-cluster` shows `Unknown` or `False`
- Downstream kustomizations blocked via `dependsOn`: n8n, pgadmin4, temporal
- Database cluster is degraded but functional (primary still serving)

## Diagnostics

```bash
# Check cluster health
kubectl get cluster postgresql-cluster -n cnpg-system

# Find the broken pod (high restart count)
kubectl get pods -n cnpg-system -l cnpg.io/cluster=postgresql-cluster

# Check WAL recovery failure in logs
kubectl logs -n cnpg-system <broken-pod> --tail=30 | grep -E "error|Error|archive recovery"

# Check which instance is the current primary (DO NOT delete this one)
kubectl get cluster postgresql-cluster -n cnpg-system -o jsonpath='{.status.currentPrimary}'
```

## Recovery Procedure

> ⚠️ **WARNING**: ONLY delete the CrashLoopBackOff pod. NEVER delete the primary (`currentPrimary` in cluster status) or a healthy running replica. Deleting the primary while replicas are degraded risks data loss.

```bash
# 1. Identify the broken instance number (N) — the one with thousands of restarts
kubectl get pods -n cnpg-system -l cnpg.io/cluster=postgresql-cluster

# 2. Force-delete the stuck pod
kubectl delete pod postgresql-cluster-N -n cnpg-system --grace-period=0 --force

# 3. Delete the stale PVC so CNPG re-provisions from the primary via pg_basebackup
kubectl delete pvc postgresql-cluster-N -n cnpg-system

# 4. Watch CNPG provision a fresh instance (will be numbered N+1)
kubectl get pods -n cnpg-system -l cnpg.io/cluster=postgresql-cluster -w
```

CNPG detects the missing PVC and automatically runs `pg_basebackup` from the current primary. No manual data restoration needed.

## Verification

```bash
kubectl get cluster postgresql-cluster -n cnpg-system
# Expected: readyInstances: 3, phase: Cluster in healthy state

flux get kustomizations -A | grep -E "postgresql|n8n|pgadmin|temporal"
# Expected: all True after ~5min
```

## Prevention

Enable CNPG barmanObjectStore backups (Tier D of the self-healing plan):
- WAL segments are continuously archived to LocalStack S3
- Recovery from archive means a corrupt replica can replay from a clean checkpoint instead of failing indefinitely

## Real Example (2026-07-02)

- Broken pod: `postgresql-cluster-4`, 4655 restarts over 21 days
- WAL checkpoint dated 2026-06-09, stuck in archive recovery since then
- Primary: `postgresql-cluster-2` (healthy throughout)
- After delete pod + PVC: CNPG provisioned `postgresql-cluster-5` in ~2min, cluster back to `readyInstances=3/3`

## References

- CNPG docs: https://cloudnative-pg.io/documentation/current/troubleshooting/
- ADR-004: Single shared PostgreSQL cluster
