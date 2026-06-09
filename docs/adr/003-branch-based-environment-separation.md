# ADR-003: Branch-Based Environment Separation

**Status:** Accepted
**Date:** 2025-01 (implemented), 2026-06 (documented as ADR)

## Context

Flux CD supports multiple patterns for environment separation:

1. **Path-based overlays** (FluxCD recommended): `apps/base/`, `apps/staging/`, `apps/production/` with Kustomize overlays
2. **Branch-based**: Different branches track different environments
3. **Repo-per-environment**: Separate Git repos per environment

We needed to separate dev (rapid iteration, single replicas, relaxed resources) from production (HA, full resources, extended retention).

## Decision

Use **branch-based separation**:
- `develop` branch → dev cluster (`clusters/stages/dev/clusters/services-amer/`)
- `main` branch → prod cluster (`clusters/stages/prod/clusters/services-amer/`)

Environment-specific config lives in:
- `clusters/stages/<env>/clusters/services-amer/environment.env` — variable overrides
- `clusters/stages/<env>/clusters/services-amer/cluster-vars-patch.yaml` — structural patches

Flux `GitRepository` sources point to different branches per environment.

## Options Considered

1. **Path-based overlays** — FluxCD's recommended pattern. Single branch, overlays in `apps/staging/`, `apps/production/`. Pros: atomic cross-env changes, single branch to manage. Cons: risk of accidentally promoting dev changes, more complex Kustomize overlay hierarchy.

2. **Branch-based** (chosen) — Each environment tracks its own branch. Pros: natural git workflow (PR from develop → main = promotion), complete isolation, no accidental cross-env contamination. Cons: potential drift between branches, merge conflicts on base changes.

3. **Repo-per-environment** — Full isolation. Overkill for a solo-developer project.

## Consequences

### Positive

- Clear promotion path: merge develop → main = deploy to prod
- Complete isolation — dev experiments never leak to prod
- Natural git workflow for a solo developer
- ConfigMap substitution (`postBuild.substituteFrom`) handles per-env values cleanly

### Negative

- Base changes must be applied to both branches (potential drift)
- Harder to see "what's different between environments" at a glance (vs overlay diffs)
- Diverges from FluxCD's officially recommended pattern (path-based)

### Mitigations

- `environment.env` keeps most per-env config as simple key-value pairs
- Structural differences (replica counts, storage sizes) are parameterized via `${VARIABLE}` substitution
- Periodic rebasing ensures branches don't drift on base configs
