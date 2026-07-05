# ADR-019: Re-enable CNPG Backups with LocalStack-Initialized S3 Credentials

**Status:** Accepted
**Date:** 2026-07-05
**Supersedes:** [ADR-017](017-cnpg-backup-deferred-for-poc.md)

## Context

Commit `80d85fb` (`feat(cnpg): enable barmanObjectStore backups to LocalStack S3 + nightly ScheduledBackup`)
re-enabled CNPG backups after ADR-017 deferred them, but did so without:

1. Superseding ADR-017 (violating the append-only ADR rule in `AGENTS.md`).
2. Adding the required `cnpg/backup/s3` Secrets Manager entry to the LocalStack startup
   script (`apps/base/localstack/helmrelease.yaml`).

The manifest changes in `80d85fb` referenced a Kubernetes Secret `cnpg-backup-s3` in the
`cnpg-system` namespace, populated by an `ExternalSecret` (`apps/base/cloudnative-pg/backup-externalsecret.yaml`)
that reads from LocalStack's Secrets Manager at key `cnpg/backup/s3`. That key was never
created anywhere, so the `ExternalSecret` sat in `SecretSyncedError` (`Secret does not exist`).

### Failure Mode Observed

After a `colima` restart on 2026-07-05, Flux re-reconciled the `postgresql-cluster` Kustomization
(`base/services/postgresql-cluster.yaml`, `wait: true`, `timeout: 15m`). Because
`ExternalSecret/cnpg-system/cnpg-backup-s3` never reached `Ready=True`, the health check
timed out after 15 minutes:

```
postgresql-cluster  False  health check failed after 15m0.007205334s:
  timeout waiting for: [ExternalSecret/cnpg-system/cnpg-backup-s3 status: 'InProgress']
```

That cascaded to every dependent Kustomization:

- `n8n` — `dependency 'flux-system/postgresql-cluster' is not ready`
- `pgadmin4` — same
- `temporal` — same

### Why LocalStack Persistence Did Not Save Us

Empirical test on 2026-07-05 (LocalStack `3.8.1` community edition, `PERSISTENCE=1`,
1Gi PVC mounted at `/var/lib/localstack/`):

- Manually created `cnpg/backup/s3` via `awslocal secretsmanager create-secret`.
- `kubectl rollout restart deployment -n localstack localstack`.
- After restart, `awslocal secretsmanager get-secret-value --secret-id cnpg/backup/s3`
  returned `ResourceNotFoundException`.
- The 15 secrets created by the startup script were re-created by the idempotent
  `create_secret` guard (`[SKIP] Already exists` for all of them, meaning the state
  survived at whatever level LocalStack persists it at). The manually-created one did not.

**Conclusion:** LocalStack community edition persistence is not a reliable substitute for
re-running the init script on every pod start. Any secret that must survive a restart
(colima restart, pod eviction, PVC re-provision, fresh cluster) MUST be declared in the
startup script.

## Decision

1. **Re-enable CNPG backups.** Keep `spec.backup.barmanObjectStore` in
   `apps/base/cloudnative-pg/postgresql-cluster.yaml` and keep the `ScheduledBackup`
   at `apps/base/cloudnative-pg/scheduledbackup.yaml` (daily 03:00 UTC, 7-day retention,
   `target: prefer-standby`).

2. **Declare the S3 credential in the LocalStack startup script.** Add:

   ```bash
   create_secret "cnpg/backup/s3" \
       "{\"access_key_id\":\"test\",\"secret_access_key\":\"test\"}" \
       "S3 credentials for CNPG barmanObjectStore backups to LocalStack"
   ```

   LocalStack accepts any credentials for its mock S3; `test`/`test` is the convention.
   The `create_secret` function is idempotent (checks `get-secret-value` first), so this
   is safe across restarts, whether persistence works or not.

3. **Establish the pattern:** Every ExternalSecret in this cluster that reads from
   LocalStack's Secrets Manager MUST have a matching `create_secret` call in the
   LocalStack startup script (`apps/base/localstack/helmrelease.yaml`). Relying on
   LocalStack persistence is not sufficient.

## Rollback

If backups need to be deferred again:

1. Remove `spec.backup.barmanObjectStore` from `postgresql-cluster.yaml`.
2. Delete `apps/base/cloudnative-pg/backup-externalsecret.yaml` and
   `apps/base/cloudnative-pg/scheduledbackup.yaml` and their entries in
   `apps/base/cloudnative-pg/kustomization.yaml`.
3. Remove the `create_secret "cnpg/backup/s3" ...` block from the LocalStack startup script.
4. Remove the `awslocal s3 mb s3://cnpg-backups` line if the bucket is no longer needed.
5. Create a new ADR superseding ADR-019.

## Consequences

### Positive

- `postgresql-cluster` Kustomization reconciles cleanly on every cluster/colima restart.
- Downstream services (`n8n`, `pgadmin4`, `temporal`) no longer block on a phantom
  ExternalSecret failure.
- `ScheduledBackup` continues to run nightly (last backup at time of writing: 43h ago,
  confirmed via `kubectl get scheduledbackup -n cnpg-system`).
- Documented pattern prevents recurrence of the same class of bug for future
  LocalStack-backed ExternalSecrets.

### Negative

- The `test`/`test` credentials are hard-coded in the startup script. Acceptable because
  LocalStack is a local mock and the value has no security meaning. If this ever runs
  against a real S3 endpoint, this secret MUST be sourced from the real Secrets Manager
  instead.

## References

- `apps/base/localstack/helmrelease.yaml` — startup script owner
- `apps/base/cloudnative-pg/postgresql-cluster.yaml` — `barmanObjectStore` config
- `apps/base/cloudnative-pg/backup-externalsecret.yaml` — ExternalSecret consumer
- `apps/base/cloudnative-pg/scheduledbackup.yaml` — nightly schedule
- `base/services/postgresql-cluster.yaml` — Kustomization with `wait: true, timeout: 15m`
- Original re-enable commit: `80d85fbc41bbd8043f5df867f279aa38e3c8c2c0`
- ADR-005 (LocalStack + ExternalSecrets pattern)
- ADR-017 (superseded by this ADR)
