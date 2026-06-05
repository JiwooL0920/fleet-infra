#!/usr/bin/env bash
set -euo pipefail

# refresh-credentials.sh
# Force-syncs ExternalSecrets from LocalStack and restarts all pods that
# consume those secrets via environment variables so the running workloads
# pick up the current credential values.
#
# Grafana is special: it persists the admin password inside grafana.db on its
# PVC. When the PVC password diverges from the K8s secret, a simple restart is
# not enough — we must reset the password via grafana cli after the pod starts.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()    { echo -e "${BLUE}ℹ  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()    { echo -e "${RED}❌ $*${NC}"; }

wait_for_rollout() {
  local ns="$1" deploy="$2" timeout="${3:-120s}"
  if ! kubectl rollout status "deployment/${deploy}" -n "${ns}" --timeout="${timeout}" 2>/dev/null; then
    fail "Rollout of ${deploy} in ${ns} did not complete within ${timeout}"
    return 1
  fi
}

secret_value() {
  local ns="$1" name="$2" key="$3"
  kubectl get secret "${name}" -n "${ns}" -o jsonpath="{.data.${key}}" 2>/dev/null | base64 -d 2>/dev/null
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if ! kubectl cluster-info &>/dev/null; then
  fail "Cannot connect to Kubernetes cluster. Is it running?"
  exit 1
fi

echo -e "${BLUE}🔄 Refreshing credentials — force-syncing secrets and restarting consumers...${NC}"
echo ""

# ---------------------------------------------------------------------------
# Step 0 — Sync CNPG-generated passwords INTO LocalStack
# ---------------------------------------------------------------------------
# CNPG auto-generates credentials stored in K8s secrets. After a restart,
# these may differ from what LocalStack has persisted. We must push the
# current CNPG password into LocalStack BEFORE ExternalSecrets re-syncs,
# otherwise stale passwords propagate to all consumers (Grafana, N8N, etc.).

info "Syncing CNPG credentials into LocalStack..."

CNPG_PASSWORD=$(secret_value cnpg-system postgresql-cluster-app password)

if [[ -z "${CNPG_PASSWORD}" ]]; then
  warn "Could not read postgresql-cluster-app secret — skipping LocalStack sync"
else
  LOCALSTACK_POD=$(kubectl get pods -n localstack -l app.kubernetes.io/name=localstack \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "${LOCALSTACK_POD}" ]]; then
    warn "LocalStack pod not found — skipping secret sync"
  else
    # CNPG secrets are managed by PushSecret (push-cnpg-app-secret) — trigger it
    if kubectl get pushsecret push-cnpg-app-secret -n cnpg-system &>/dev/null; then
      kubectl annotate pushsecret push-cnpg-app-secret -n cnpg-system \
        force-sync="$(date +%s)" --overwrite >/dev/null 2>&1
      sleep 3
      PS_STATUS=$(kubectl get pushsecret push-cnpg-app-secret -n cnpg-system \
        -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "")
      if [[ "${PS_STATUS}" == "Synced" ]]; then
        echo "  push-cnpg-app-secret: synced"
      else
        warn "  push-cnpg-app-secret: ${PS_STATUS:-unknown} — CNPG secrets may be stale"
      fi
    else
      warn "  PushSecret push-cnpg-app-secret not found — skipping CNPG sync"
    fi

    # grafana/database/password is NOT managed by PushSecret — sync directly
    if ! kubectl exec -n localstack "${LOCALSTACK_POD}" -- \
        awslocal secretsmanager put-secret-value \
        --secret-id "grafana/database/password" \
        --secret-string "${CNPG_PASSWORD}" \
        --region us-east-1 >/dev/null 2>&1; then
      kubectl exec -n localstack "${LOCALSTACK_POD}" -- \
        awslocal secretsmanager create-secret \
        --name "grafana/database/password" \
        --secret-string "${CNPG_PASSWORD}" \
        --region us-east-1 >/dev/null 2>&1 && \
        echo "  created grafana/database/password" || \
        warn "  failed to sync grafana/database/password"
    else
      echo "  updated grafana/database/password"
    fi

    success "CNPG credential sync complete"
  fi
fi

# Sync GitHub PAT into LocalStack (from the bootstrap K8s secret)
GITHUB_PAT_TOKEN=$(secret_value localstack github-pat-bootstrap token)
if [[ -n "${GITHUB_PAT_TOKEN}" && -n "${LOCALSTACK_POD:-}" ]]; then
  if ! kubectl exec -n localstack "${LOCALSTACK_POD}" -- \
      awslocal secretsmanager put-secret-value \
      --secret-id "github/mcp/token" \
      --secret-string "{\"GITHUB_PERSONAL_ACCESS_TOKEN\":\"${GITHUB_PAT_TOKEN}\"}" \
      --region us-east-1 >/dev/null 2>&1; then
    kubectl exec -n localstack "${LOCALSTACK_POD}" -- \
      awslocal secretsmanager create-secret \
      --name "github/mcp/token" \
      --secret-string "{\"GITHUB_PERSONAL_ACCESS_TOKEN\":\"${GITHUB_PAT_TOKEN}\"}" \
      --region us-east-1 >/dev/null 2>&1 && \
      echo "  created github/mcp/token" || \
      warn "  failed to sync github/mcp/token"
  else
    echo "  updated github/mcp/token"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 1 — Force-sync every ExternalSecret
# ---------------------------------------------------------------------------

info "Force-syncing all ExternalSecrets..."

NAMESPACES=$(kubectl get externalsecrets --all-namespaces --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name 2>/dev/null)

if [[ -z "${NAMESPACES}" ]]; then
  warn "No ExternalSecrets found — nothing to sync."
else
  while IFS= read -r line; do
    ns=$(echo "${line}" | awk '{print $1}')
    name=$(echo "${line}" | awk '{print $2}')
    kubectl annotate externalsecret "${name}" -n "${ns}" \
      force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 && \
      echo "  synced ${ns}/${name}" || \
      warn "  failed to annotate ${ns}/${name}"
  done <<< "${NAMESPACES}"

  # Give ESO a moment to reconcile
  sleep 5
  success "ExternalSecrets synced"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2 — Restart deployments that consume secrets via env vars
# ---------------------------------------------------------------------------

# Map: namespace/deployment pairs
# Only services that inject secrets through secretKeyRef (env vars).
# Traefik uses a Middleware that reads the secret directly — no restart needed.
SECRET_CONSUMERS=(
  "monitoring/monitoring-kube-prometheus-stack-grafana"
  "pgadmin4/pgadmin4"
  "n8n/n8n"
)

# Temporal has multiple deployments sharing the same secret
TEMPORAL_DEPLOYS=$(kubectl get deploy -n temporal --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)

info "Restarting secret-consuming deployments..."

for entry in "${SECRET_CONSUMERS[@]}"; do
  ns="${entry%%/*}"
  deploy="${entry#*/}"
  if kubectl get deployment "${deploy}" -n "${ns}" &>/dev/null; then
    kubectl rollout restart "deployment/${deploy}" -n "${ns}" >/dev/null
    echo "  restarted ${ns}/${deploy}"
  else
    warn "  ${ns}/${deploy} not found — skipping"
  fi
done

# Restart all Temporal deployments
if [[ -n "${TEMPORAL_DEPLOYS}" ]]; then
  while IFS= read -r deploy; do
    [[ -z "${deploy}" ]] && continue
    kubectl rollout restart "deployment/${deploy}" -n temporal >/dev/null
    echo "  restarted temporal/${deploy}"
  done <<< "${TEMPORAL_DEPLOYS}"
fi

# Also restart kagent if it exists (consumes kagent-postgres-credentials)
if kubectl get deployment kagent -n kagent &>/dev/null; then
  kubectl rollout restart deployment/kagent -n kagent >/dev/null
  echo "  restarted kagent/kagent"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3 — Wait for rollouts
# ---------------------------------------------------------------------------

info "Waiting for rollouts to complete..."

for ns in "${!SECRET_CONSUMERS[@]}"; do
  deploy="${SECRET_CONSUMERS[$ns]}"
  if kubectl get deployment "${deploy}" -n "${ns}" &>/dev/null; then
    wait_for_rollout "${ns}" "${deploy}" "180s" && \
      echo "  ${ns}/${deploy} ready" || true
  fi
done

if [[ -n "${TEMPORAL_DEPLOYS}" ]]; then
  while IFS= read -r deploy; do
    [[ -z "${deploy}" ]] && continue
    wait_for_rollout "temporal" "${deploy}" "180s" && \
      echo "  temporal/${deploy} ready" || true
  done <<< "${TEMPORAL_DEPLOYS}"
fi

if kubectl get deployment kagent -n kagent &>/dev/null; then
  wait_for_rollout "kagent" "kagent" "180s" && \
    echo "  kagent/kagent ready" || true
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4 — Grafana: reset admin password in persistent DB
# ---------------------------------------------------------------------------
# Grafana stores the admin password hash in grafana.db on its PVC.
# GF_SECURITY_ADMIN_PASSWORD is only used on initial DB creation.
# After a restart the env var is correct but grafana.db may still hold
# a stale hash. We use `grafana cli` to force-reset it.

info "Resetting Grafana admin password in persistent database..."

GRAFANA_DEPLOY="monitoring-kube-prometheus-stack-grafana"
GRAFANA_NS="monitoring"

if kubectl get deployment "${GRAFANA_DEPLOY}" -n "${GRAFANA_NS}" &>/dev/null; then
  GRAFANA_PWD=$(secret_value "${GRAFANA_NS}" "grafana-admin-credentials" "admin-password")

  if [[ -z "${GRAFANA_PWD}" ]]; then
    warn "Could not read grafana-admin-credentials secret — skipping password reset"
  else
    # Wait for the grafana container to be ready
    kubectl wait --for=condition=ready pod \
      -l app.kubernetes.io/name=grafana \
      -n "${GRAFANA_NS}" \
      --timeout=120s >/dev/null 2>&1 || true

    # Give Grafana a moment to finish its DB migrations
    sleep 5

    if kubectl exec -n "${GRAFANA_NS}" "deployment/${GRAFANA_DEPLOY}" -c grafana -- \
        grafana cli admin reset-admin-password "${GRAFANA_PWD}" >/dev/null 2>&1; then
      success "Grafana admin password synced with K8s secret"
    else
      warn "grafana cli reset failed — you may need to delete the Grafana PVC and restart"
      warn "  kubectl scale deploy/${GRAFANA_DEPLOY} -n ${GRAFANA_NS} --replicas=0"
      warn "  kubectl delete pvc ${GRAFANA_DEPLOY} -n ${GRAFANA_NS}"
      warn "  kubectl scale deploy/${GRAFANA_DEPLOY} -n ${GRAFANA_NS} --replicas=1"
    fi
  fi
else
  warn "Grafana deployment not found — skipping"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 5 — pgAdmin4: reset internal SQLite DB if password drifted
# ---------------------------------------------------------------------------
# pgAdmin4 persists its admin password in /var/lib/pgadmin/pgadmin4.db on its
# PVC. The PGADMIN_DEFAULT_PASSWORD env var is only used on initial DB creation.
# If the K8s secret rotated, the internal DB still holds the old hash.
# Fix: delete pgadmin4.db and restart — pgAdmin re-initializes from env vars.

PGADMIN_DEPLOY="pgadmin4"
PGADMIN_NS="pgadmin4"

if kubectl get deployment "${PGADMIN_DEPLOY}" -n "${PGADMIN_NS}" &>/dev/null; then
  info "Checking pgAdmin4 credential alignment..."

  PGADMIN_K8S_PASS=$(secret_value "${PGADMIN_NS}" "pgadmin4-credentials" "password")
  PGADMIN_POD_PASS=$(kubectl exec -n "${PGADMIN_NS}" "deploy/${PGADMIN_DEPLOY}" -- \
    printenv PGADMIN_DEFAULT_PASSWORD 2>/dev/null || echo "")

  if [[ -n "${PGADMIN_K8S_PASS}" && "${PGADMIN_K8S_PASS}" != "${PGADMIN_POD_PASS}" ]]; then
    info "pgAdmin4 password drifted — resetting internal database..."
    PGADMIN_POD_NAME=$(kubectl get pods -n "${PGADMIN_NS}" -l app.kubernetes.io/name=pgadmin4 \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "${PGADMIN_POD_NAME}" ]]; then
      kubectl exec -n "${PGADMIN_NS}" "${PGADMIN_POD_NAME}" -- \
        rm -f /var/lib/pgadmin/pgadmin4.db 2>/dev/null || true
      kubectl delete pod -n "${PGADMIN_NS}" "${PGADMIN_POD_NAME}" --grace-period=5 >/dev/null 2>&1
      wait_for_rollout "${PGADMIN_NS}" "${PGADMIN_DEPLOY}" "60s" && \
        success "pgAdmin4 re-initialized with current credentials" || \
        warn "pgAdmin4 rollout timed out"
    else
      warn "pgAdmin4 pod not found — skipping reset"
    fi
  else
    success "pgAdmin4 credentials already aligned"
  fi
else
  warn "pgAdmin4 deployment not found — skipping"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 6 — Verify
# ---------------------------------------------------------------------------

info "Verifying credentials match between K8s secrets and running pods..."
echo ""

ISSUES=0

# Grafana
GRAFANA_K8S=$(secret_value monitoring grafana-admin-credentials admin-password)
GRAFANA_POD=$(kubectl exec -n monitoring "deployment/${GRAFANA_DEPLOY}" -c grafana -- printenv GF_SECURITY_ADMIN_PASSWORD 2>/dev/null || echo "")
if [[ -n "${GRAFANA_K8S}" && "${GRAFANA_K8S}" == "${GRAFANA_POD}" ]]; then
  echo -e "  Grafana env       ${GREEN}✓${NC}"
else
  echo -e "  Grafana env       ${RED}✗ mismatch${NC}"
  ((ISSUES++)) || true
fi

# Verify Grafana API login
HTTP_CODE=$(kubectl exec -n monitoring "deployment/${GRAFANA_DEPLOY}" -c grafana -- \
  curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:3000/api/org" -u "admin:${GRAFANA_K8S}" 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
  echo -e "  Grafana login     ${GREEN}✓${NC}"
else
  echo -e "  Grafana login     ${RED}✗ HTTP ${HTTP_CODE}${NC}"
  ((ISSUES++)) || true
fi

# pgAdmin4
PGADMIN_K8S=$(secret_value pgadmin4 pgadmin4-credentials password)
PGADMIN_POD=$(kubectl exec -n pgadmin4 deploy/pgadmin4 -- printenv PGADMIN_DEFAULT_PASSWORD 2>/dev/null || echo "")
if [[ -n "${PGADMIN_K8S}" && "${PGADMIN_K8S}" == "${PGADMIN_POD}" ]]; then
  echo -e "  pgAdmin4          ${GREEN}✓${NC}"
else
  echo -e "  pgAdmin4          ${RED}✗ mismatch${NC}"
  ((ISSUES++)) || true
fi

# N8N (postgres password)
N8N_K8S=$(secret_value n8n n8n-postgres-credentials POSTGRES_PASSWORD)
N8N_POD=$(kubectl exec -n n8n deploy/n8n -- printenv DB_POSTGRESDB_PASSWORD 2>/dev/null || echo "")
if [[ -n "${N8N_K8S}" && "${N8N_K8S}" == "${N8N_POD}" ]]; then
  echo -e "  N8N (db creds)    ${GREEN}✓${NC}"
else
  echo -e "  N8N (db creds)    ${RED}✗ mismatch${NC}"
  ((ISSUES++)) || true
fi

echo ""

if [[ ${ISSUES} -eq 0 ]]; then
  success "All credentials are in sync!"
else
  warn "${ISSUES} credential(s) still out of sync — check above for details"
fi

echo ""
echo -e "${BLUE}💡 Run 'make get-ui-credentials' to see the current credentials.${NC}"
