#!/bin/bash
set -e

echo "🔐 Initializing Traefik Dashboard secrets in LocalStack..."

# Check if environment variables are set
if [ -z "$TRAEFIK_DASHBOARD_USERNAME" ] || [ -z "$TRAEFIK_DASHBOARD_PASSWORD" ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_USERNAME and TRAEFIK_DASHBOARD_PASSWORD environment variables must be set"
    echo "Please set them in your ~/.zshrc:"
    echo "export TRAEFIK_DASHBOARD_USERNAME=\"admin\""
    echo "export TRAEFIK_DASHBOARD_PASSWORD=\"your-secure-password\""
    exit 1
fi

# Wait for LocalStack to be ready
echo "⏳ Waiting for LocalStack to be ready..."
until curl -s http://localhost:4566/_localstack/health | grep -q '"secretsmanager".*"running\|available"'; do
    echo "Waiting for LocalStack Secrets Manager..."
    sleep 2
done

echo "✅ LocalStack is ready!"

# Generate htpasswd format for Basic Auth
# Using openssl passwd for compatibility (available on most systems)
HTPASSWD_ENTRY="$TRAEFIK_DASHBOARD_USERNAME:$(openssl passwd -apr1 "$TRAEFIK_DASHBOARD_PASSWORD")"

# Create secrets in LocalStack Secrets Manager
echo "👤 Creating Traefik dashboard username secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "traefik/dashboard/credentials/username" \
    --secret-string "$TRAEFIK_DASHBOARD_USERNAME" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "traefik/dashboard/credentials/username" \
    --secret-string "$TRAEFIK_DASHBOARD_USERNAME" \
    --region us-east-1

echo "🔑 Creating Traefik dashboard password secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "traefik/dashboard/credentials/password" \
    --secret-string "$TRAEFIK_DASHBOARD_PASSWORD" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "traefik/dashboard/credentials/password" \
    --secret-string "$TRAEFIK_DASHBOARD_PASSWORD" \
    --region us-east-1

echo "🛡️ Creating Traefik dashboard htpasswd secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "traefik/dashboard/credentials/htpasswd" \
    --secret-string "$HTPASSWD_ENTRY" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "traefik/dashboard/credentials/htpasswd" \
    --secret-string "$HTPASSWD_ENTRY" \
    --region us-east-1

echo "✅ Traefik dashboard secrets successfully created/updated in LocalStack!"
echo "👤 Username: $TRAEFIK_DASHBOARD_USERNAME"
echo "🔒 Password: [HIDDEN]"
echo "🛡️ htpasswd: [HIDDEN]"