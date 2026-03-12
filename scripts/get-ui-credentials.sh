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
PGADMIN_EMAIL=$(kubectl get secret pgadmin4-credentials -n pgadmin4 -o jsonpath='{.data.email}' 2>/dev/null | base64 -d 2>/dev/null) || PGADMIN_EMAIL="(secret not found)"
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
echo "  RedisInsight (http://redis.local)     - no auth
    Redis connection: redis-sentinel.redis-sentinel:26379 (Sentinel, master group: mymaster)"
echo "  Jaeger       (http://jaeger.local)    - no auth"
