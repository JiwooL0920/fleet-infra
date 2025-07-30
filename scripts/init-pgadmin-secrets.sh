#!/bin/bash
set -e

echo "🔐 Initializing pgAdmin4 secrets in LocalStack..."

# Check if environment variables are set
if [ -z "$PGADMIN_EMAIL" ] || [ -z "$PGADMIN_PASSWORD" ]; then
    echo "❌ Error: PGADMIN_EMAIL and PGADMIN_PASSWORD environment variables must be set"
    echo "Please set them in your ~/.zshrc:"
    echo "export PGADMIN_EMAIL=\"admin@fleet-infra.local\""
    echo "export PGADMIN_PASSWORD=\"your-secure-password\""
    exit 1
fi

# Wait for LocalStack to be ready
echo "⏳ Waiting for LocalStack to be ready..."
until curl -s http://localhost:4566/_localstack/health | grep -q '"secretsmanager".*"running\|available"'; do
    echo "Waiting for LocalStack Secrets Manager..."
    sleep 2
done

echo "✅ LocalStack is ready!"

# Create secrets in LocalStack Secrets Manager
echo "📝 Creating pgAdmin4 email secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "pgadmin4/credentials/email" \
    --secret-string "$PGADMIN_EMAIL" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "pgadmin4/credentials/email" \
    --secret-string "$PGADMIN_EMAIL" \
    --region us-east-1

echo "🔑 Creating pgAdmin4 password secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "pgadmin4/credentials/password" \
    --secret-string "$PGADMIN_PASSWORD" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "pgadmin4/credentials/password" \
    --secret-string "$PGADMIN_PASSWORD" \
    --region us-east-1

echo "✅ pgAdmin4 secrets successfully created/updated in LocalStack!"
echo "📧 Email: $PGADMIN_EMAIL"
echo "🔒 Password: [HIDDEN]"