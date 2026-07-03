# AGENTS.md — fleet-infra

Context and rules for AI agents (Cursor, opencode) working in this repository.

## Repository at a Glance

Kubernetes GitOps infrastructure using Flux CD. Several dozen services are deployed via fine-grained
`dependsOn` dependency chains. See `service-catalog.json` / `base/services/kustomization.yaml` for current counts and enablement, and `CLAUDE.md` for the full architecture reference.

**Key directories:**
- `apps/base/<svc>/` — Kubernetes manifests per service (HelmRelease, namespace, etc.)
- `base/services/<svc>.yaml` — Flux Kustomization with `dependsOn` wiring
- `base/services/kustomization.yaml` — master resource list (enable/disable services here)
- `docs/adr/` — Architecture Decision Records (append-only log)
- `clusters/stages/` — environment-specific overrides (dev tracks `develop`, prod tracks `main`)

## Documentation Discipline

**Rule: every infra change that ships must have a corresponding doc update.**

| Change type | Required doc update |
|---|---|
| New service added | `README.md` service list, new `docs/adr/<NNN>-<topic>.md`, `CLAUDE.md` if architecture changes |
| Service config changed significantly | Update relevant `docs/adr/` entry or create a superseding ADR |
| Service removed / disabled | Note in `README.md`, mark old ADR as Deprecated/Superseded |
| Dependency graph changed | Update `CLAUDE.md` architecture section |
| Trivial bump (chart version, replica count) | No doc update required |

**ADR rules:**
- ADRs are **append-only**. Never edit an accepted decision.
- To change a decision: create a new ADR with `**Status:** Accepted` and link it: `Supersedes ADR-NNN`.
- Mark the old ADR: `**Status:** Superseded by ADR-NNN`.
- The ADR index at `docs/adr/README.md` is auto-generated — do not edit it manually.

**Pre-push enforcement:**
A `pre-push` hook (`scripts/pre-commit/check-docs-freshness.sh`) will block the push if infra
files changed without any doc update. Run `make docs-draft` to get AI-drafted suggestions when blocked.

## GitOps Principles

- **Never apply changes directly to the cluster.** All changes go through Git → PR → Flux reconcile.
- When creating new services, follow the template in `CLAUDE.md` ("Adding New Applications").
- Use `dependsOn` to declare direct dependencies only — no transitive chains.
- Services are enabled/disabled in `base/services/kustomization.yaml` (comment/uncomment).

## Secrets

- No secrets in Git. Secrets are managed by ExternalSecrets Operator pulling from LocalStack.
- Startup scripts in LocalStack auto-create secrets; no manual initialization needed.
- Exception: run `make setup-github-secret` once after a fresh cluster to enable gitops-agent.

## Branch Strategy

- `develop` → dev cluster (auto-deploys on push)
- `main` → prod cluster (auto-deploys on push)
- Feature branches: branch from `develop`, PR back to `develop`.

## AI Agent Permissions

| Operation | Allowed without approval |
|---|---|
| Read any file | Yes |
| Edit `apps/base/` manifests | Yes (local only — changes go through PR) |
| Edit `base/services/` kustomizations | Yes |
| Edit `docs/adr/` | Yes — but follow append-only rule |
| `kubectl apply` or direct cluster mutations | **Never** |
| `git push` directly to `main` | **Never** |
| Create PRs | Yes, via gitops-agent → GitHub MCP |
