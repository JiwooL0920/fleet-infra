# ADR-001: Fine-Grained Service-Level Dependencies

**Status:** Accepted
**Date:** 2025-01 (implemented), 2026-06 (documented as ADR)

## Context

The original Flux CD deployment used a 5-wave sequential architecture:

```
Wave 1 (5m) → Wave 2 (10m) → Wave 3 (5m) → Wave 4 (10m) → Wave 5 (5m)
```

Problems:
- **30-45 minute deployments** due to sequential wave processing
- Services waited for entire waves, not their actual dependencies (e.g., pgAdmin4 waited for Redis even though it only needs PostgreSQL)
- Parallel-ready services forced into sequential execution
- Slow developer feedback loops

## Decision

Replace coarse-grained wave dependencies with fine-grained service-level `dependsOn` declarations in individual Flux Kustomizations.

Each service declares only its **direct** dependencies:

```yaml
# base/services/pgadmin4.yaml
spec:
  dependsOn:
    - name: postgresql-cluster  # Only what it actually needs
```

Structure: one Kustomization per service in `base/services/`, aggregated by `base/services/kustomization.yaml`.

## Consequences

### Positive

- **65-75% faster deployments** (8-12 min vs 30-45 min)
- 10+ services deploy in parallel when dependencies allow
- Adding new services requires declaring only true dependencies
- Clear dependency graph — easy to reason about startup order

### Negative

- More YAML files (one per service vs 5 wave files)
- Must be careful with dependency accuracy — missing a dep causes startup failures
- `postBuild.substituteFrom` ConfigMap must be available in flux-system namespace

### Deployment Flow (current)

```
T+0:00  Foundation (8 services parallel): traefik, localstack, cnpg-op, scylla-op,
        external-secrets-op, external-secrets-config, traefik-config, metrics-server
T+2:30  Monitoring: kube-prometheus-stack, weave-gitops
T+3:00  Databases: postgresql-cluster, redis-sentinel, scylla-cluster
T+5:30  Applications: n8n, temporal, kagent, ollama
T+8:00  UIs + observability: pgadmin4, redisinsight, kubescape, opencost
```
