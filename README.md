GitOps infrastructure platform to manage 10+ services across multi-environment Kubernetes clusters with automated deployment, monitoring, and high availability. Used to host personal projects on local machine and quick POCs

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

**Quick Start:**

```bash
# Install pre-commit
brew install pre-commit

# Install required tools
brew install kubeconform kustomize yq yamllint shellcheck markdownlint-cli detect-secrets

# Install hooks
pre-commit install

# Create secrets baseline
detect-secrets scan > .secrets.baseline
```

**Run hooks manually:**

```bash
# Run on all files
pre-commit run --all-files

# Run on staged files only
pre-commit run
```

**What gets checked:**
- YAML syntax and formatting
- Kubernetes/Flux manifest validation
- Kustomize overlay validation
- Flux API version compatibility
- Secret detection (AWS keys, private keys, etc.)
- Markdown and shell script linting
- File formatting (trailing whitespace, EOF)

For detailed documentation, see [Pre-commit Hooks Guide](docs/PRE_COMMIT_HOOKS.md).
