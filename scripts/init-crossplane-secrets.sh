#!/bin/bash
set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"

echo "🔐 Initializing Crossplane AWS credentials in LocalStack..."

# Create Crossplane AWS credentials for LocalStack
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "crossplane/aws" \
  --description "Crossplane AWS provider credentials" \
  --secret-string '{"access_key_id":"test","secret_access_key":"test"}' \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "crossplane/aws" \
  --secret-string '{"access_key_id":"test","secret_access_key":"test"}' \
  --region us-east-1

echo "✅ Crossplane secrets initialized successfully"