GitOps infrastructure platform to manage 10+ services across multi-environment Kubernetes clusters with automated deployment, monitoring, and high availability. Used to host personal projects on local machine and quick POCs

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

### Create Kind Cluster

- Run `kind create cluster --config kind-config.yaml`
- Verify creation with `kind get clusters` and `kubectl get nodes`

### Bootstrap Flux on the Cluster

- Install flux controllers on your cluster
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
- Kubernetes/Flux manifest validation
- Kustomize overlay validation
- Flux API version compatibility
- Secret detection (AWS keys, private keys, etc.)
- Markdown and shell script linting
- File formatting (trailing whitespace, EOF)

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
