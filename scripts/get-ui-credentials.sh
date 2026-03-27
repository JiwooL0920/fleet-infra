#!/usr/bin/env bash
set -euo pipefail

# Get login credentials for all UI services in the cluster

echo "=== Fleet-Infra UI Service Credentials ==="
echo ""

# --- Grafana ---
echo "Grafana (http://grafana.local)"
GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null) || GRAFANA_USER="(secret not found)"
GRAFANA_PASS=$(kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null) || GRAFANA_PASS="(secret not found)"
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
