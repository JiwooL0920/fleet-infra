# ADR-005: LocalStack + External Secrets for Development Secrets

**Status:** Accepted
**Date:** 2025-01 (implemented), 2026-06 (documented as ADR)

## Context

Kubernetes services need secrets (database passwords, API keys, admin credentials). In production these come from a real secrets manager (AWS Secrets Manager, Vault, etc.). For local development, we need a pattern that:

1. Doesn't commit plaintext secrets to Git
2. Is portable to production (same ExternalSecret manifests work)
3. Auto-initializes on fresh cluster startup
4. Requires no manual secret creation steps

## Decision

Use **LocalStack** (AWS Secrets Manager emulation) + **External Secrets Operator** with a `ClusterSecretStore` pointing to LocalStack.

Architecture:
```
LocalStack (port 4566)
  └── AWS Secrets Manager API
       └── Secrets auto-created by startup hooks (enableStartupScripts)
            └── ClusterSecretStore (localstack-secretstore)
                 └── ExternalSecret per service → Kubernetes Secret
```

Secrets are idempotently created by LocalStack init scripts on pod startup. LocalStack persistence ensures secrets survive restarts.

## Options Considered

1. **SOPS-encrypted secrets in Git** — Encrypt secrets with age/GPG, decrypt at deploy time. Pros: secrets in Git (auditable), no external dependency. Cons: key management overhead, not production-portable (production uses real secrets manager), awkward workflow for rotation.

2. **Sealed Secrets** — Encrypt with cluster-specific key, commit sealed secret. Pros: GitOps-native. Cons: cluster-specific keys (can't share between environments), no production portability, limited lifecycle management.

3. **HashiCorp Vault** — Full secrets management platform. Overkill for local dev. Heavy resource usage.

4. **LocalStack + External Secrets** (chosen) — Same ExternalSecret manifests work locally (pointing to LocalStack) and in production (pointing to real AWS). Secrets auto-initialize. Zero manual steps after `make setup-github-secret`.

## Consequences

### Positive

- **Production-portable**: Same `ExternalSecret` YAMLs work in production by swapping `ClusterSecretStore` to point at real AWS
- **Zero-touch initialization**: Secrets auto-created on cluster startup via LocalStack hooks
- **Idempotent**: Safe to restart, re-deploy, or rebuild cluster
- **Standard API**: Uses real AWS Secrets Manager API (just against LocalStack endpoint)
- **Persistent**: LocalStack persists data across pod restarts

### Negative

- LocalStack resource overhead (~200MB RAM) for emulating AWS APIs
- Slight behavioral differences between LocalStack and real AWS Secrets Manager
- Test credentials (`test`/`test`) committed for LocalStack auth (acceptable for local dev)
- GitHub PAT requires one-time manual setup (`make setup-github-secret`)

### Security Note

LocalStack credentials in Git are intentionally `test`/`test` — they only authenticate against the local emulator. Production uses IAM roles or real credential injection.
