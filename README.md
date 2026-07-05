GitOps infrastructure platform to manage several dozen services across multi-environment Kubernetes clusters with automated deployment, monitoring, and high availability. Used to host personal projects on local machine and quick POCs. See `service-catalog.json` for the current service inventory.

# Prerequisites

Before setting up the infrastructure, install the required tools:

## Core Tools

```bash
# Kubernetes tools
brew install kubectl kind flux

# Container runtime
brew install colima
# or use Docker Desktop
```

## Development Tools

```bash
# Pre-commit and validation tools
brew install pre-commit kubeconform kustomize yq

# Linters
brew install yamllint shellcheck markdownlint-cli

# Security scanning
brew install detect-secrets

# AWS CLI (for LocalStack)
brew install awscli
```

## Verification

```bash
# Check tool versions
kubectl version --client
kind version
flux version
pre-commit --version
kubeconform -v
kustomize version
yq --version
```

# How to set up

### Start Docker Engine

- Adjust configuration for colima: `colima edit` or `vi ~/.colima/default/colima.yaml`
- **Recommended resources:** 8 CPU, 16GB RAM, 80GB disk (6 CPU, 12GB RAM, 60GB disk minimum)
- Run `colima start`
- Check status with `colima list`

### Create Kind clusters

Use [terraform-infra](https://github.com/JiwooL0920/terraform-infra) to provision both clusters and register the spoke with Argo CD in one workflow:

- **`dev-services-amer`** (hub, 80/443) — where Flux runs and the platform services (including Argo CD) are deployed
- **`dev-applications`** (spoke, 8081/8444) — Argo CD-managed workload target; runs alongside the hub on distinct host ports

First-time apply is two-phase (see terraform-infra README) because the Kubernetes provider needs the spoke context to exist at plan time. Subsequent applies are single-phase.

Verify with `kind get clusters` and `kubectl config get-contexts` — you should see both `kind-dev-services-amer` and `kind-dev-applications`.

### Bootstrap Flux on the hub cluster

- Install flux controllers on **`kind-dev-services-amer`** only (not the spoke).
- Connect Flux to your GitHub repo
- Track the `develop` branch
- Deploy everything in `clusters/stages/dev/clusters/services-amer`

```bash
flux bootstrap github \
    --owner=<your-github-username> \
    --repository=fleet-infra \
    --branch=develop \
    --path=./clusters/stages/dev/clusters/services-amer \
    --personal
```

### Wait for Flux to Deploy Everything

- `flux get all --watch`
- `flux get kustomizations`
- `flux get helmreleases -A`

### Run post-setup scripts

- Fix controlplane IP (if needed): `make fix-control-plane`

**Note:** Secrets are now automatically initialized by LocalStack startup hooks. No manual initialization needed.

### Setup Local DNS for Traefik Ingress (Recommended)

Setup local DNS entries to access services via Traefik without port forwarding:

```bash
make setup-dns
```

This adds `.local` domain entries to `/etc/hosts`, allowing you to access services at:
- `http://argocd.local` - Argo CD (spoke app sync on hub)
- `http://grafana.local` - Grafana
- `http://prometheus.local` - Prometheus
- `http://n8n.local` - N8N
- `http://temporal.local` - Temporal UI
- `http://traefik.local` - Traefik Dashboard
- And more...

**Note:** Traefik must be configured with NodePort for this to work (already configured in dev environment).

### Alternative: Start Port Forwarding

If you prefer traditional port forwarding instead of DNS setup:

- `make port-forward`

### Argo CD spoke (fully automated by terraform-infra)

When `terraform apply` in terraform-infra runs, it also:

1. Creates an `argocd-manager` ServiceAccount + `cluster-admin` ClusterRoleBinding on the spoke
2. Provisions a `kubernetes.io/service-account-token` Secret on the spoke (the K8s controller auto-populates the token)
3. Reads the token back and writes an Argo CD Cluster Secret (`dev-applications`, labelled `argocd.argoproj.io/secret-type=cluster`) directly onto the hub

Argo CD picks up the labelled Secret and registers the spoke automatically. Application manifests for the spoke live in [argocd-applications](https://github.com/JiwooL0920/argocd-applications) (`develop` → `metadata/dev-applications/`).

**No manual bootstrap step in fleet-infra** — the previous `make register-app-cluster` was removed. See [ADR-018](docs/adr/018-terraform-provisioned-argocd-cluster-secret.md) for the full rationale and the trade-offs versus the enterprise workload-identity pattern.

Hub Argo CD does **not** run a bundled Redis pod: it uses the shared **Redis Sentinel** stack via the standard `redis-sentinel` ClusterIP service (port 6379), same cluster as other workloads. See [ADR-015](docs/adr/015-disable-redis-sentinel-masterservice.md).

## Development Workflow

### Pre-commit Hooks

This repository uses pre-commit hooks to validate changes before committing. This ensures code quality and catches issues early.

**Installation:**

```bash
# Option 1: Use Makefile (recommended)
make precommit-install

# Option 2: Manual installation
brew install pre-commit kubeconform kustomize yq yamllint shellcheck markdownlint-cli detect-secrets
pre-commit install
detect-secrets scan > .secrets.baseline
```

**Usage:**

```bash
# Run on all files
make precommit-run
# or
pre-commit run --all-files

# Run on staged files only
make precommit-run-staged
# or
pre-commit run

# Update hooks to latest versions
make precommit-update

# Clean and reinstall
make precommit-clean
```

**What gets checked:**
- YAML syntax and formatting
- Kubernetes/Flux manifest validation (kubeconform + `flux build kustomization` for `apps/base/`)
- Kustomize overlay validation
- Flux API version compatibility (no `v1beta2`/`v2beta2` drift)
- Secret detection via `detect-secrets` (AWS keys, private keys, high-entropy strings)
- Markdown and shell script linting (shellcheck at `warning` severity)
- File formatting (trailing whitespace, EOF newline, YAML syntax)
- Service catalog freshness (regenerates `service-catalog.json` and fails if stale)
- ADR index freshness (regenerates `docs/adr/README.md` when ADRs change)

**Validation only (without pre-commit):**

```bash
# Validate all manifests
make validate-all

# Individual validations
make validate-manifests  # Kubeconform validation
make validate-flux       # Flux API version check
make validate-kustomize  # Kustomize overlay build
```

For detailed documentation, see [Pre-commit Hooks Guide](docs/PRE_COMMIT_HOOKS.md).

## Architecture Decisions

Significant architecture choices live in [`docs/adr/`](docs/adr/) as append-only ADRs. Notable recent ones:

- **[ADR-005](docs/adr/005-localstack-external-secrets.md)** — LocalStack + ExternalSecrets as the canonical dev-secret pattern
- **[ADR-013](docs/adr/013-argocd-hub-spoke-applications.md)** — Argo CD hub-spoke topology for application workloads
- **[ADR-015](docs/adr/015-disable-redis-sentinel-masterservice.md)** — Argo CD reuses shared Redis Sentinel (no bundled Redis)
- **[ADR-016](docs/adr/016-externalsecrets-migration-hardcoded-credentials.md)** — Migrated n8n / weave-gitops / pgadmin4 committed credentials to ExternalSecrets
- **[ADR-018](docs/adr/018-terraform-provisioned-argocd-cluster-secret.md)** — Argo CD spoke registration moved to Terraform (replaces the removed `make register-app-cluster` bootstrap)
- **[ADR-019](docs/adr/019-cnpg-backups-reenabled-localstack-init-secret.md)** — CloudNative-PG backups re-enabled; every LocalStack-backed ExternalSecret must be seeded by the LocalStack startup script (supersedes ADR-017)

See [`docs/adr/README.md`](docs/adr/README.md) for the full auto-generated index.
