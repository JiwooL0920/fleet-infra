# ADR-020: Grafana DB Password Sourced from CNPG PushSecret (Not LocalStack Init)

**Status:** Accepted
**Date:** 2026-07-15

## Context

`grafana-sa-setup` Kustomization got permanently stuck in `Unknown / Reconciliation in progress`
after every `colima` restart. The stall was caused by a credential chain that had two independent
sources of truth for the same password, guaranteed to diverge on any restart:

```
[LocalStack startup script]                [CNPG operator]
    gen_password()                            auto-generates PG app password
        │                                          │
        ▼                                          ▼
LocalStack SM                              Secret cnpg-system/
  grafana/database/password                  postgresql-cluster-app
        │                                          │
        ▼                                          │
ExternalSecret                                     │
  monitoring/grafana-db-credentials  ◄─── DIFFERENT VALUE ───┘
        │                                          │
        ▼                                          ▼
Grafana pod env GF_DATABASE_PASSWORD       Actual password in PG
                                            └── auth failure → CrashLoopBackOff
```

### Observed Failure Chain

1. Colima restart wipes ephemeral state; LocalStack’s `startupScriptContent` re-ran and
   `create_secret` reseeded `grafana/database/password` with a fresh random value (or the
   persisted value from an earlier init that never matched CNPG in the first place).
2. `ExternalSecret grafana-db-credentials` synced this random value into
   `monitoring/grafana-db-credentials`.
3. CNPG cluster PVC persisted the original `app` user password.
4. Grafana consumed the ExternalSecret’s value, tried to authenticate to Postgres, and got
   `pq: password authentication failed for user "app"` → `CrashLoopBackOff`.
5. `create-grafana-sa-token` Job’s `reset-admin-password` init container ran
   `kubectl exec … -c grafana` against the crashed pod → `container not found` → Job
   `Failed` → Kustomization health check stalled indefinitely (`wait: true`,
   `timeout: 5m`, `retry every 1m` — replayed the same failure forever).

The workaround was `make refresh-credentials` after every restart. That script explicitly
copied `postgresql-cluster-app.data.password` into `grafana/database/password`. Documented,
manual, and not GitOps-native.

### Why the Old Design Existed

Historical: `grafana-db-credentials` predated the `push-cnpg-app-secret` PushSecret. At the
time, the only way to get the PG password into LocalStack was a manual `make setup-grafana-db`
bootstrap run once per cluster. When ADR-016 introduced the CNPG PushSecret pattern for n8n /
kagent / temporal, `grafana-db-credentials` was not migrated.

## Decision

Change `apps/base/kube-prometheus-stack/externalsecret-grafana-db.yaml` to source `password`
from `cnpg/postgresql-cluster-app/password` — the same LocalStack key that
`push-cnpg-app-secret` (`apps/base/cloudnative-pg/push-secret.yaml`) auto-populates from the
CNPG-generated `postgresql-cluster-app` Secret. Adopt the pattern already used by
`n8n-postgres-credentials` and `kagent-postgres-credentials`.

Complementary hardening in the same change:

- `apps/base/grafana-sa-setup/job.yaml`: `reset-admin-password` init container now polls for a
  Ready Grafana pod (up to ~4 min, within the 5-min Job timeout) instead of fail-fast on
  first `container not found`. Filter is on `containerStatuses[?(@.name=="grafana")].ready==true`
  so crash-looping pods are (correctly) skipped, not selected as `.items[0]`.
- `base/services/kube-prometheus-stack.yaml`: add explicit
  `dependsOn: postgresql-cluster` (makes the cross-Kustomization dependency on the PushSecret
  chain explicit rather than implicit-via-pod-restart-loop); correct the Grafana health check
  Deployment name from `kube-prometheus-stack-grafana` to
  `monitoring-kube-prometheus-stack-grafana` (Helm release fullname). The old wrong name
  silently no-oped, allowing the Kustomization to report `Ready` while Grafana was crashed.
- Dead-code removal: `grafana/database/password` init block in
  `apps/base/localstack/helmrelease.yaml`, `grafana/database/password` special-case sync in
  `scripts/refresh-credentials.sh`, `scripts/init-grafana-db-secret.sh`, `make setup-grafana-db`
  target, and matching help text / README references.

## Consequences

### Positive

- **Idempotent on any restart.** No manual `make setup-grafana-db`, no `make refresh-credentials`.
  Colima restart → PushSecret re-syncs (interval 1h, also on-demand via ESO reconcile) →
  ExternalSecret pulls the current value → Grafana authenticates → Job runs → Kustomization
  Ready.
- **Single source of truth.** Whatever password CNPG stores in `postgresql-cluster-app` is
  what Grafana uses. Zero drift possible.
- **Consistency.** All PG consumers (n8n, kagent, temporal, grafana) now share the same
  credential-sourcing pattern.
- **Fail-loud on real problems.** Fixed Grafana health check will now surface actual Grafana
  outages via Flux instead of silently reporting Ready.

### Negative / Trade-offs

- Adds an explicit cross-Kustomization dependency (`kube-prometheus-stack` → `postgresql-cluster`).
  Cold-boot ordering now serializes monitoring behind DB — but monitoring was already
  functionally blocked on DB anyway; this just encodes reality.
- On the very first `colima start` before PushSecret has run its first reconcile,
  `grafana-db-credentials` ExternalSecret will be in `SecretSyncedError` until PushSecret
  populates the LocalStack key. `dependsOn: postgresql-cluster` closes this race by ensuring
  `kube-prometheus-stack` waits for the postgresql-cluster Kustomization (which owns the
  PushSecret) to be Ready first.

### Migration

Existing clusters:

1. Merge this change; Flux applies the updated ExternalSecret manifest.
2. ESO reconciles `grafana-db-credentials` from the new key. If
   `cnpg/postgresql-cluster-app/password` already exists in LocalStack (PushSecret has run
   at least once — usually true on any cluster older than ~1h), the Secret is corrected
   immediately.
3. Grafana rollout restart is triggered by the label `cnpg.io/reload: "true"` on the target
   Secret template. On existing clusters, if the Secret was previously created without that
   template, a manual `kubectl rollout restart deploy/monitoring-kube-prometheus-stack-grafana -n monitoring`
   may be needed once.
4. `create-grafana-sa-token` Job’s new wait-loop will pick up the healthy Grafana pod and
   complete; Kustomization `grafana-sa-setup` transitions from `Unknown` to `Ready`.

Fresh clusters:

- No changes to bootstrap steps. `make setup-grafana-db` no longer exists and is no longer
  needed.
