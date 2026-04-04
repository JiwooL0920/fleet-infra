#!/usr/bin/env bash
# init-grafana-db-secret.sh
# Read the PostgreSQL app password from the CNPG cluster secret and store it
# in LocalStack Secrets Manager so ExternalSecrets can sync it to the
# monitoring namespace for Grafana's database backend.
#
# This follows the same "secret zero" bootstrap pattern as init-github-secret.sh:
# - CNPG auto-generates the password (stored in K8s Secret)
# - This script copies it into LocalStack
# - ExternalSecret grafana-db-credentials syncs it to monitoring namespace
# - Grafana reads it via envValueFrom
#
# Run once per fresh cluster (or whenever the PG cluster is recreated):
#   make setup-grafana-db

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()    { echo -e "${RED}❌ $*${NC}"; }

if ! kubectl cluster-info &>/dev/null; then
    fail "Cannot connect to Kubernetes cluster. Is it running?"
    exit 1
fi

info "Reading PostgreSQL app password from cnpg-system/postgresql-cluster-app..."

PG_PASSWORD=$(kubectl get secret postgresql-cluster-app -n cnpg-system \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || true

if [[ -z "${PG_PASSWORD}" ]]; then
    fail "Could not read postgresql-cluster-app secret in cnpg-system namespace."
    echo "  Is the PostgreSQL cluster running?"
    echo "    kubectl get cluster -n cnpg-system"
    exit 1
fi

info "Password read successfully (${#PG_PASSWORD} chars)"

info "Storing password in LocalStack as grafana/database/password..."

kubectl exec -n localstack deployment/localstack -- \
    awslocal secretsmanager create-secret \
        --name "grafana/database/password" \
        --description "PostgreSQL app password for Grafana database backend" \
        --secret-string "${PG_PASSWORD}" \
        --region us-east-1 2>/dev/null || \
kubectl exec -n localstack deployment/localstack -- \
    awslocal secretsmanager put-secret-value \
        --secret-id "grafana/database/password" \
        --secret-string "${PG_PASSWORD}" \
        --region us-east-1 >/dev/null

success "grafana/database/password stored in LocalStack"

echo ""
if kubectl get externalsecret grafana-db-credentials -n monitoring &>/dev/null 2>&1; then
    info "Triggering ExternalSecret sync for grafana-db-credentials..."
    kubectl annotate externalsecret grafana-db-credentials -n monitoring \
        force-sync="$(date +%s)" --overwrite >/dev/null
    sleep 3
    if kubectl get secret grafana-db-credentials -n monitoring &>/dev/null 2>&1; then
        success "grafana-db-credentials secret is ready in monitoring namespace"
    else
        warn "Secret not yet synced — ExternalSecret may still be reconciling."
        warn "Check: kubectl get externalsecret grafana-db-credentials -n monitoring"
    fi
else
    info "ExternalSecret grafana-db-credentials not found yet — will sync after Flux deploys it."
fi

echo ""
success "Grafana database secret bootstrap complete!"
echo ""
echo "  What was created:"
echo "    LocalStack:    grafana/database/password (PG app password)"
echo "    K8s Secret:    monitoring/grafana-db-credentials (synced by ExternalSecrets)"
echo ""
echo "  Grafana will use this to connect to PostgreSQL instead of SQLite."
echo "  This is a one-time bootstrap step per cluster."
