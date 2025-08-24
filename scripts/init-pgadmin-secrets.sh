#!/bin/bash
set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"

echo "🔐 Initializing pgAdmin4 secrets in LocalStack..."

# Create pgAdmin4 credentials
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "pgadmin4/credentials/email" \
  --description "pgAdmin4 default admin email" \
  --secret-string "admin@example.com" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "pgadmin4/credentials/email" \
  --secret-string "admin@example.com" \
  --region us-east-1

aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "pgadmin4/credentials/password" \
  --description "pgAdmin4 default admin password" \
  --secret-string "admin123" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "pgadmin4/credentials/password" \
  --secret-string "admin123" \
  --region us-east-1

echo "✅ pgAdmin4 secrets initialized successfully"