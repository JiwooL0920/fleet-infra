#!/usr/bin/env bash
# init-github-secret.sh
# Create the github-pat-bootstrap Kubernetes Secret in the localstack namespace.
# LocalStack reads GITHUB_PAT from this secret on startup and creates
# the github/mcp/token entry in its Secrets Manager, which ExternalSecrets
# then syncs to the kagent namespace as github-mcp-credentials.
#
# This follows the same "secret zero" bootstrap pattern as Flux SSH keys:
# - The K8s Secret is created once, outside of Git (never committed)
# - The code that reads it (LocalStack startup script) IS in Git
# - LocalStack persistence means this survives pod restarts
# - On a fresh cluster, re-run this script once
#
# Token resolution order:
#   1. GITHUB_TOKEN env var
#   2. GITHUB_PAT env var
#   3. Prompt the user

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---------------------------------------------------------------------------
# Resolve GitHub token
# ---------------------------------------------------------------------------
TOKEN=""

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    TOKEN="${GITHUB_TOKEN}"
    info "Using GITHUB_TOKEN from environment"
elif [[ -n "${GITHUB_PAT:-}" ]]; then
    TOKEN="${GITHUB_PAT}"
    info "Using GITHUB_PAT from environment"
else
    warn "No GITHUB_TOKEN or GITHUB_PAT found in environment."
    echo ""
    echo "  To set permanently, add to ~/.zshrc:"
    echo "    export GITHUB_TOKEN=\"ghp_yourTokenHere\""
    echo ""
    read -r -p "  Enter your GitHub PAT now (or press Enter to skip): " TOKEN
    echo ""
    if [[ -z "${TOKEN}" ]]; then
        warn "Skipping GitHub secret initialization."
        echo ""
        echo "  Run this later when your token is available:"
        echo "    make setup-github-secret"
        exit 0
    fi
fi

# Basic token format validation
if [[ ! "${TOKEN}" =~ ^(ghp_|github_pat_|gho_) ]]; then
    warn "Token does not look like a valid GitHub PAT (expected ghp_, github_pat_, or gho_ prefix)."
    read -r -p "  Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! kubectl cluster-info &>/dev/null; then
    fail "Cannot connect to Kubernetes cluster. Is it running?"
    exit 1
fi

# Ensure the localstack namespace exists (may not be created by Flux yet)
kubectl create namespace localstack --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ---------------------------------------------------------------------------
# Create / update the github-pat-bootstrap K8s Secret
# ---------------------------------------------------------------------------
info "Creating github-pat-bootstrap Secret in localstack namespace..."

# Pipe token via stdin (--from-file=token=/dev/stdin) so it never appears in
# process argv. `ps auxww` would otherwise expose the token from the earlier
# create-secret CLI flag approach (see git blame for pre-Wave-2C history).
printf '%s' "${TOKEN}" | kubectl create secret generic github-pat-bootstrap \
    --namespace localstack \
    --from-file=token=/dev/stdin \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null

success "github-pat-bootstrap Secret created/updated in localstack namespace"

# ---------------------------------------------------------------------------
# Restart LocalStack so its startup script re-runs with the new env var
# ---------------------------------------------------------------------------
echo ""
if kubectl get deployment localstack -n localstack &>/dev/null 2>&1; then
    info "Restarting LocalStack to pick up the new secret..."
    kubectl rollout restart deployment/localstack -n localstack >/dev/null
    info "Waiting for LocalStack to be ready (up to 90s)..."
    if kubectl rollout status deployment/localstack -n localstack --timeout=90s >/dev/null; then
        success "LocalStack restarted and ready"
    else
        warn "LocalStack rollout timed out — check: kubectl get pods -n localstack"
    fi
else
    info "LocalStack not yet deployed — the secret will be available when it starts."
    info "Flux will deploy LocalStack and read GITHUB_PAT automatically."
fi

# ---------------------------------------------------------------------------
# Trigger ExternalSecret sync for github-mcp-credentials
# ---------------------------------------------------------------------------
echo ""
if kubectl get externalsecret github-mcp-credentials -n kagent &>/dev/null 2>&1; then
    info "Triggering ExternalSecret sync for github-mcp-credentials..."
    kubectl annotate externalsecret github-mcp-credentials -n kagent \
        force-sync="$(date +%s)" --overwrite >/dev/null
    sleep 3
    if kubectl get secret github-mcp-credentials -n kagent &>/dev/null 2>&1; then
        success "github-mcp-credentials secret is ready in Kubernetes"
    else
        warn "Secret not yet synced — LocalStack may still be initializing."
        warn "Check: kubectl get externalsecret github-mcp-credentials -n kagent"
    fi
else
    info "kagent ExternalSecret not found yet — will sync when kagent is deployed."
fi

echo ""
success "GitHub PAT bootstrap complete!"
echo ""
echo "  What was created:"
echo "    K8s Secret:    localstack/github-pat-bootstrap (read by LocalStack on startup)"
echo "    LocalStack:    github/mcp/token (created by startup script from GITHUB_PAT env)"
echo "    K8s Secret:    kagent/github-mcp-credentials (synced by ExternalSecrets)"
echo ""
echo "  This is a one-time bootstrap step. LocalStack persistence means the"
echo "  LocalStack secret survives pod restarts — only re-run on a fresh cluster."
