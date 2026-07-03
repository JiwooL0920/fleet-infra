# ADR-017: Defer CNPG Backup Configuration for POC Cluster

**Status:** Accepted
**Date:** 2026-07-03

## Context

Both the March 2026 audit and the July 2026 follow-up audit flagged a documentation-to-manifest mismatch:

- `docs/audit_031226_1773354880.md` notes backup claims in docs that are not implemented in manifests.
- `apps/base/cloudnative-pg/postgresql-cluster.yaml` defines the CNPG `Cluster` but has no `backup` section.
- No `ScheduledBackup` resource is currently defined for the CNPG cluster.

At the same time, repository docs (notably `CLAUDE.md`) have claimed:

- automated PostgreSQL backups to LocalStack S3,
- daily schedule,
- 30-day retention.

Those claims are not true for the current deployed state.

## Decision

For the current POC/dev scope, defer implementing CNPG backup resources (`barmanObjectStore` and `ScheduledBackup`).

Instead:

1. Remove backup automation/retention claims that imply an implemented CNPG backup pipeline.
2. Keep this deferment explicit in architecture docs via this ADR.
3. Revisit when backup/recovery objectives become concrete (e.g., defined RPO/RTO requirements, persistent non-ephemeral workload data).

## Rollback / Future Activation Path

When backups become required, implement the CNPG-native backup path and supersede this ADR:

1. Add `spec.backup.barmanObjectStore` to `apps/base/cloudnative-pg/postgresql-cluster.yaml` targeting LocalStack S3 (or the target object store for that environment).
2. Add one or more CNPG `ScheduledBackup` resources with an explicit schedule/retention policy aligned to documented RPO/RTO.
3. Update docs to reflect implemented behavior only after manifests are merged and reconciled.
4. Create a new ADR superseding ADR-017 with final backup architecture decisions.

## Consequences

### Positive

- Docs now match deployed manifests (no false confidence about recovery posture).
- Avoids adding backup complexity to a POC cluster before requirements exist.

### Negative

- Current CNPG posture has no declarative scheduled base backups/WAL archival configured.
- If persistent data value increases before backups are implemented, recovery capability may be insufficient.

## References

- `docs/audit_031226_1773354880.md`
- `apps/base/cloudnative-pg/postgresql-cluster.yaml`
- CloudNativePG backup documentation: https://cloudnative-pg.io/docs/current/backup/
