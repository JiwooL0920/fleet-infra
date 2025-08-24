#!/bin/bash
set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"

echo "🔐 Initializing Grafana secrets in LocalStack..."

# Create Grafana admin credentials
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "grafana/admin/credentials/username" \
  --description "Grafana admin username" \
  --secret-string "admin" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "grafana/admin/credentials/username" \
  --secret-string "admin" \
  --region us-east-1

aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "grafana/admin/credentials/password" \
  --description "Grafana admin password" \
  --secret-string "admin123" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "grafana/admin/credentials/password" \
  --secret-string "admin123" \
  --region us-east-1

echo "✅ Grafana secrets initialized successfully"