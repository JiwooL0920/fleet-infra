#!/bin/bash
set -e

echo "🔐 Initializing Grafana admin secrets in LocalStack..."

# Default secure credentials (can be overridden with environment variables)
GRAFANA_ADMIN_USERNAME="${GRAFANA_ADMIN_USERNAME:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)}"

echo "👤 Using admin username: $GRAFANA_ADMIN_USERNAME"
echo "🔑 Generated secure admin password (hidden for security)"

# Wait for LocalStack to be ready
echo "⏳ Waiting for LocalStack to be ready..."
until curl -s http://localhost:4566/_localstack/health | grep -q '"secretsmanager".*"running\|available"'; do
    echo "Waiting for LocalStack Secrets Manager..."
    sleep 2
done

echo "✅ LocalStack is ready!"

# Create secrets in LocalStack Secrets Manager
echo "👤 Creating Grafana admin username secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "grafana/admin/credentials/username" \
    --secret-string "$GRAFANA_ADMIN_USERNAME" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "grafana/admin/credentials/username" \
    --secret-string "$GRAFANA_ADMIN_USERNAME" \
    --region us-east-1

echo "🔑 Creating Grafana admin password secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "grafana/admin/credentials/password" \
    --secret-string "$GRAFANA_ADMIN_PASSWORD" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "grafana/admin/credentials/password" \
    --secret-string "$GRAFANA_ADMIN_PASSWORD" \
    --region us-east-1

echo "✅ Grafana admin secrets successfully created/updated in LocalStack!"
echo "👤 Username: $GRAFANA_ADMIN_USERNAME"
echo "🔒 Password: [HIDDEN FOR SECURITY]"
echo ""
echo "📝 To retrieve the password later, run:"
echo "aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id grafana/admin/credentials/password --region us-east-1 --query SecretString --output text"