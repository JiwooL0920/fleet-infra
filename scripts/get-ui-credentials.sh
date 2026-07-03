#!/usr/bin/env bash
set -euo pipefail

# Get login credentials for all UI services in the cluster.
#
# Before printing any credential, we:
#  1. Force-sync all ExternalSecrets so Kubernetes secrets match LocalStack
#  2. For Grafana specifically: reset the Grafana DB password to match the
#     secret (Grafana persists its admin hash in PostgreSQL; the env var is
#     only applied on first boot, so it drifts after restarts/rotations).

# ---------------------------------------------------------------------------
# Step 1: force-sync all ExternalSecrets and wait for Ready
# ---------------------------------------------------------------------------
echo "Syncing ExternalSecrets..." >&2
TS="$(date +%s)"
kubectl annotate externalsecret grafana-admin-credentials     -n monitoring force-sync="${TS}" --overwrite 2>/dev/null || true
kubectl annotate externalsecret pgadmin4-credentials          -n pgadmin4   force-sync="${TS}" --overwrite 2>/dev/null || true
kubectl annotate externalsecret traefik-dashboard-credentials -n traefik    force-sync="${TS}" --overwrite 2>/dev/null || true

# Wait up to 15s for grafana-admin-credentials to be Ready (most critical)
for _ in $(seq 1 15); do
  STATUS=$(kubectl get externalsecret grafana-admin-credentials -n monitoring \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  [ "${STATUS}" = "True" ] && break
  sleep 1
done
echo "ExternalSecrets synced." >&2
echo "" >&2

# ---------------------------------------------------------------------------
# Step 2: align Grafana DB password with the (now-fresh) Kubernetes secret
# ---------------------------------------------------------------------------
# Grafana stores admin password as a hash in PostgreSQL. The env var
# GF_SECURITY_ADMIN_PASSWORD only seeds it on first boot, so it drifts.
# We use `grafana cli admin reset-admin-password` to bring the DB in sync.
GRAFANA_POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
GRAFANA_SECRET_PASS=$(kubectl get secret grafana-admin-credentials -n monitoring \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "${GRAFANA_POD}" ] && [ -n "${GRAFANA_SECRET_PASS}" ]; then
  echo "Aligning Grafana DB password with secret..." >&2
  echo "${GRAFANA_SECRET_PASS}" | kubectl exec -i -n monitoring "${GRAFANA_POD}" -c grafana -- \
    grafana cli admin reset-admin-password --password-from-stdin >/dev/null 2>&1 && \
    echo "Grafana password aligned." >&2 || \
    echo "Warning: could not reset Grafana DB password (pod may be restarting)." >&2
fi
echo "" >&2

# ---------------------------------------------------------------------------
# Credentials output
# ---------------------------------------------------------------------------
echo "=== Fleet-Infra UI Service Credentials ==="
echo ""

# --- Grafana ---
echo "Grafana (http://grafana.local)"
GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null) || GRAFANA_USER="(secret not found)"
GRAFANA_PASS="${GRAFANA_SECRET_PASS:-$(kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null)}"
echo "  Username: ${GRAFANA_USER}"
echo "  Password: ${GRAFANA_PASS}"
echo ""

# --- Traefik Dashboard ---
echo "Traefik Dashboard (http://traefik.local)"
TRAEFIK_HTPASSWD=$(kubectl get secret traefik-dashboard-credentials -n traefik -o jsonpath='{.data.users}' 2>/dev/null | base64 -d 2>/dev/null) || TRAEFIK_HTPASSWD=""
if [ -n "${TRAEFIK_HTPASSWD}" ]; then
  TRAEFIK_USER=$(echo "${TRAEFIK_HTPASSWD}" | cut -d: -f1)
  TRAEFIK_PASS=$(kubectl exec -n localstack deploy/localstack -- \
    awslocal secretsmanager get-secret-value \
    --secret-id traefik/dashboard/credentials/password \
    --query SecretString --output text 2>/dev/null) || TRAEFIK_PASS="(run: kubectl port-forward -n localstack svc/localstack 4566:4566 && aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id traefik/dashboard/credentials/password --region us-east-1 --query SecretString --output text)"
  echo "  Username: ${TRAEFIK_USER}"
  echo "  Password: ${TRAEFIK_PASS}"
else
  echo "  (secret not found)"
fi
echo ""

# --- pgAdmin4 ---
echo "pgAdmin4 (http://pgadmin.local)"
PGADMIN_EMAIL=$(kubectl exec -n pgadmin4 deploy/pgadmin4 -- printenv PGADMIN_DEFAULT_EMAIL 2>/dev/null) || PGADMIN_EMAIL="(pod not running)"
PGADMIN_PASS=$(kubectl get secret pgadmin4-credentials -n pgadmin4 -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || PGADMIN_PASS="(secret not found)"
echo "  Email:    ${PGADMIN_EMAIL}"
echo "  Password: ${PGADMIN_PASS}"
echo ""

# --- Weave GitOps ---
echo "Weave GitOps (http://weave.local)"
echo "  Username: admin"
echo "  Password: admin"
echo ""

# --- No auth required ---
echo "--- No authentication required ---"
echo "  N8N          (http://n8n.local)       - owner setup on first launch"
echo "  Temporal UI  (http://temporal.local)  - no auth"
echo "  Prometheus   (http://prometheus.local) - no auth"
echo "  AlertManager (http://alertmanager.local) - no auth"
echo "  RedisInsight (http://redis.local)     - no auth"
echo "    Redis connection: redis-sentinel.redis-sentinel:26379 (Sentinel, master group: mymaster)"
echo "  Jaeger       (http://jaeger.local)    - no auth"
echo ""

echo "=== Database Connections ==="
echo ""
echo "PostgreSQL (from pgAdmin4 or any in-cluster client)"
PG_USER=$(kubectl get secret postgresql-cluster-app -n cnpg-system -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null) || PG_USER="(secret not found)"
PG_PASS=$(kubectl get secret postgresql-cluster-app -n cnpg-system -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null) || PG_PASS="(secret not found)"
echo "  Host:     postgresql-cluster-rw.cnpg-system.svc.cluster.local"
echo "  Port:     5432"
echo "  Username: ${PG_USER}"
echo "  Password: ${PG_PASS}"
echo "  Databases: appdb, n8n, temporal, temporal_visibility"
echo ""
echo "Redis Sentinel (from RedisInsight or any in-cluster client)"
echo "  Host:         redis-sentinel.redis-sentinel.svc.cluster.local"
echo "  Sentinel Port: 26379"
echo "  Data Port:    6379"
echo "  Master Group: mymaster"
echo "  Auth:         none"
