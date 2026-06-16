#!/usr/bin/env bash
# register-app-cluster.sh
# One-time bootstrap: create spoke ServiceAccount token, store in LocalStack Secrets Manager,
# then force-sync the hub ExternalSecret so Argo CD can register cluster "dev-applications".
#
# Prerequisites:
#   - Hub cluster: kind-dev-services-amer (Flux + LocalStack + External Secrets)
#   - Spoke cluster: kind-dev-applications (terraform second KIND module)
#   - jq installed
#
# Usage:
#   ./scripts/register-app-cluster.sh
#   SPOKE_CONTEXT=kind-dev-applications HUB_CONTEXT=kind-dev-services-amer ./scripts/register-app-cluster.sh

set -euo pipefail

SPOKE_CONTEXT="${SPOKE_CONTEXT:-kind-dev-applications}"
HUB_CONTEXT="${HUB_CONTEXT:-kind-dev-services-amer}"
SECRET_ID="${ARGOCD_SPOKE_SECRET_ID:-argocd/clusters/dev-applications}"
LOCALSTACK_NS="${LOCALSTACK_NS:-localstack}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
info() { echo -e "${BLUE}ℹ  $*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}"; }

if ! command -v jq &>/dev/null; then
  fail "jq is required (brew install jq)"
  exit 1
fi

for ctx in "$SPOKE_CONTEXT" "$HUB_CONTEXT"; do
  if ! kubectl config get-contexts "$ctx" &>/dev/null; then
    fail "kubectl context not found: $ctx"
    exit 1
  fi
done

info "Ensuring argocd-manager ServiceAccount on spoke ($SPOKE_CONTEXT)..."
kubectl --context "$SPOKE_CONTEXT" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-argocd-remote
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

info "Minting long-lived bearer token (spoke)..."
if ! TOKEN="$(kubectl --context "$SPOKE_CONTEXT" create token argocd-manager -n kube-system --duration=720h 2>/dev/null)"; then
  fail "kubectl create token failed (need kubectl 1.24+). Alternatively create a Secret of type kubernetes.io/service-account-token."
  exit 1
fi

if [[ -z "$TOKEN" ]]; then
  fail "Empty token from kubectl create token"
  exit 1
fi

if ! kubectl --context "$HUB_CONTEXT" get deployment -n "$LOCALSTACK_NS" localstack &>/dev/null; then
  fail "LocalStack deployment not found on hub ($HUB_CONTEXT). Wait for Flux to deploy localstack."
  exit 1
fi

SECRET_JSON="$(jq -n --arg token "$TOKEN" '{token:$token}')"

info "Writing secret to LocalStack ($SECRET_ID) via awslocal in localstack pod..."
set +e
OUT_CREATE="$(kubectl --context "$HUB_CONTEXT" exec -n "$LOCALSTACK_NS" deploy/localstack -- \
  awslocal secretsmanager create-secret --name "$SECRET_ID" --secret-string "$SECRET_JSON" --region us-east-1 2>&1)"
RC_CREATE=$?
set -e

if [[ $RC_CREATE -eq 0 ]]; then
  ok "Created secret in LocalStack"
else
  if echo "$OUT_CREATE" | grep -qi "already exists\|ResourceExistsException"; then
    info "Secret exists; updating value..."
    kubectl --context "$HUB_CONTEXT" exec -n "$LOCALSTACK_NS" deploy/localstack -- \
      awslocal secretsmanager put-secret-value --secret-id "$SECRET_ID" --secret-string "$SECRET_JSON" --region us-east-1
    ok "Updated secret in LocalStack"
  else
    fail "LocalStack create-secret failed: $OUT_CREATE"
    exit 1
  fi
fi

if kubectl --context "$HUB_CONTEXT" get externalsecret argocd-cluster-dev-applications -n argocd &>/dev/null; then
  info "Force-sync ExternalSecret on hub..."
  kubectl --context "$HUB_CONTEXT" annotate externalsecret argocd-cluster-dev-applications -n argocd \
    force-sync="$(date +%s)" --overwrite
  ok "ExternalSecret annotated — Argo CD cluster secret should appear within ~1m"
else
  warn "ExternalSecret argocd-cluster-dev-applications not found yet (deploy argocd + argocd-cluster-config first)."
fi

echo ""
ok "Done. In Argo CD UI, cluster dev-applications should show Connected once the secret syncs."
