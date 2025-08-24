#!/bin/bash
set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"

echo "🔐 Initializing Redis secrets in LocalStack..."

# Create Redis password
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "redis/credentials/password" \
  --description "Redis authentication password" \
  --secret-string "redis123" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "redis/credentials/password" \
  --secret-string "redis123" \
  --region us-east-1

echo "✅ Redis secrets initialized successfully"