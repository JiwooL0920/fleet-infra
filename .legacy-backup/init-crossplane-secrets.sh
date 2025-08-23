#!/bin/bash
set -e

echo "🔐 Initializing Crossplane AWS secrets in LocalStack..."

# Check if LocalStack is running
if ! curl -s http://localhost:4566/_localstack/health > /dev/null; then
    echo "❌ LocalStack is not accessible at localhost:4566"
    echo "   Please make sure LocalStack is running and port forwarding is active."
    echo "   Run: kubectl port-forward svc/localstack -n localstack 4566:4566"
    exit 1
fi

# Generate secure AWS credentials for Crossplane/Terraform
ACCESS_KEY_ID=$(openssl rand -hex 16)
SECRET_ACCESS_KEY=$(openssl rand -base64 32)

# Create the Crossplane AWS secrets in LocalStack Secrets Manager
echo "📝 Creating crossplane/aws secret in LocalStack..."
aws --endpoint-url=http://localhost:4566 \
    secretsmanager create-secret \
    --name "crossplane/aws" \
    --description "AWS credentials for Crossplane Terraform provider" \
    --secret-string "{\"access_key_id\":\"$ACCESS_KEY_ID\",\"secret_access_key\":\"$SECRET_ACCESS_KEY\"}" \
    --region us-east-1 \
    --no-cli-pager || \
aws --endpoint-url=http://localhost:4566 \
    secretsmanager update-secret \
    --secret-id "crossplane/aws" \
    --secret-string "{\"access_key_id\":\"$ACCESS_KEY_ID\",\"secret_access_key\":\"$SECRET_ACCESS_KEY\"}" \
    --region us-east-1 \
    --no-cli-pager

echo "✅ Crossplane AWS secrets created successfully!"
echo "   Access Key ID: $ACCESS_KEY_ID"
echo "   Secret Access Key: [REDACTED - stored securely in LocalStack]"
echo ""
echo "🔄 External Secrets Operator will automatically sync these to Kubernetes secrets."
echo "   The secrets will be available as 'terraform-aws-credentials' in crossplane-system namespace."
echo ""
echo "💡 Test your Crossplane setup with:"
echo "   kubectl apply -f apps/base/crossplane/crossplane-config/test-bucket.yaml"