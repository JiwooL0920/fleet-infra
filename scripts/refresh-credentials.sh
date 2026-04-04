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
# Step 5 — Verify
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
