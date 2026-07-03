# Archived Applications

This directory holds app manifests that are no longer active in the Flux service graph.

## Archival policy

- We only move a service into `apps/archived/<name>/` when it is fully unreferenced from active manifests and documentation.
- If any YAML/Markdown/Makefile reference exists, we **do not archive** in order to avoid dangling paths.

## Restore procedure

To restore an archived app:

1. Move it back to `apps/base/<name>/`.
2. Re-enable or add the corresponding `base/services/<name>.yaml` entry.
3. Add it to `base/services/kustomization.yaml`.
4. Run validation:
   - `make validate-kustomize`
   - `make validate-flux`

## Session 3 (Wave 4A T28)

Candidates were pre-validated with repository and prod-stage grep checks.
All six candidates were **skipped** for now because references still exist.
