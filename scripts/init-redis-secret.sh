#!/bin/bash
set -e

echo "🔐 Initializing Redis secrets in LocalStack..."

# Check if environment variables are set
if [ -z "$REDIS_PASSWORD" ]; then
    echo "❌ Error: REDIS_PASSWORD environment variable must be set"
    echo "Please set it in your ~/.zshrc:"
    echo "export REDIS_PASSWORD=\"your-secure-redis-password\""
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
echo "🔑 Creating Redis password secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "redis/credentials/password" \
    --secret-string "$REDIS_PASSWORD" \
    --region us-east-1 || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
    --secret-id "redis/credentials/password" \
    --secret-string "$REDIS_PASSWORD" \
    --region us-east-1

echo "✅ Redis secrets successfully created/updated in LocalStack!"
echo "🔒 Password: [HIDDEN]"