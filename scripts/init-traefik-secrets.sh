#!/bin/bash
set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"

echo "🔐 Initializing Traefik secrets in LocalStack..."

# Generate htpasswd for admin:admin123
HTPASSWD_HASH='admin:$2y$10$8K8BXuP4QOGVne8qB5gXxOzBeJp7AJvqOZFuBjdl.9pK3L4xf7gq.'

# Create Traefik dashboard credentials
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "traefik/dashboard/credentials/username" \
  --description "Traefik dashboard username" \
  --secret-string "admin" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "traefik/dashboard/credentials/username" \
  --secret-string "admin" \
  --region us-east-1

aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "traefik/dashboard/credentials/password" \
  --description "Traefik dashboard password" \
  --secret-string "admin123" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "traefik/dashboard/credentials/password" \
  --secret-string "admin123" \
  --region us-east-1

aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager create-secret \
  --name "traefik/dashboard/credentials/htpasswd" \
  --description "Traefik dashboard htpasswd hash" \
  --secret-string "$HTPASSWD_HASH" \
  --region us-east-1 2>/dev/null || \
aws --endpoint-url=$LOCALSTACK_ENDPOINT secretsmanager update-secret \
  --secret-id "traefik/dashboard/credentials/htpasswd" \
  --secret-string "$HTPASSWD_HASH" \
  --region us-east-1

echo "✅ Traefik secrets initialized successfully"