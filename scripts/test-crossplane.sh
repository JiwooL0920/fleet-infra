#!/bin/bash

# Test script for Crossplane installation and functionality
# This script validates that Crossplane is properly installed and can provision resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo "========================================="
echo "Crossplane Installation Test Suite"
echo "========================================="
echo ""

# Function to run a test
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -n "Testing: $test_name..."
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e " ${RED}✗${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to check resource status
check_resource_status() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-""}
    
    if [ -n "$namespace" ]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"
    else
        kubectl get "$resource_type" "$resource_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"
    fi
}

echo "${BLUE}1. Core Components${NC}"
echo "-----------------"

# Test 1: Crossplane namespace exists
run_test "Crossplane namespace exists" \
    "kubectl get namespace crossplane-system"

# Test 2: Crossplane deployment is running
run_test "Crossplane deployment running" \
    "kubectl get deployment crossplane -n crossplane-system -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -q True"

# Test 3: Crossplane RBAC manager is running
run_test "RBAC manager deployment running" \
    "kubectl get deployment crossplane-rbac-manager -n crossplane-system -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -q True"

# Test 4: Crossplane pods are ready
run_test "All Crossplane pods ready" \
    "kubectl wait --for=condition=Ready pod -l app=crossplane -n crossplane-system --timeout=10s"

echo ""
echo "${BLUE}2. Providers${NC}"
echo "------------"

# Test 5: AWS S3 Provider installed
run_test "AWS S3 Provider installed" \
    "kubectl get provider provider-aws-s3 -o jsonpath='{.status.conditions[?(@.type==\"Installed\")].status}' | grep -q True"

# Test 6: AWS S3 Provider healthy
run_test "AWS S3 Provider healthy" \
    "kubectl get provider provider-aws-s3 -o jsonpath='{.status.conditions[?(@.type==\"Healthy\")].status}' | grep -q True"

# Test 7: AWS IAM Provider installed
run_test "AWS IAM Provider installed" \
    "kubectl get provider provider-aws-iam -o jsonpath='{.status.conditions[?(@.type==\"Installed\")].status}' | grep -q True"

# Test 8: AWS IAM Provider healthy
run_test "AWS IAM Provider healthy" \
    "kubectl get provider provider-aws-iam -o jsonpath='{.status.conditions[?(@.type==\"Healthy\")].status}' | grep -q True"

# Test 9: AWS EC2 Provider installed
run_test "AWS EC2 Provider installed" \
    "kubectl get provider provider-aws-ec2 -o jsonpath='{.status.conditions[?(@.type==\"Installed\")].status}' | grep -q True"

# Test 10: AWS EC2 Provider healthy
run_test "AWS EC2 Provider healthy" \
    "kubectl get provider provider-aws-ec2 -o jsonpath='{.status.conditions[?(@.type==\"Healthy\")].status}' | grep -q True"

echo ""
echo "${BLUE}3. Provider Configuration${NC}"
echo "------------------------"

# Test 11: ProviderConfig exists
run_test "Default ProviderConfig exists" \
    "kubectl get providerconfig default"

# Test 12: AWS credentials secret exists
run_test "AWS credentials secret exists" \
    "kubectl get secret aws-credentials -n crossplane-system"

# Test 13: External Secret for AWS credentials
run_test "External Secret for AWS creds synced" \
    "kubectl get externalsecret crossplane-aws-credentials -n crossplane-system -o jsonpath='{.status.conditions[?(@.type==\"SecretSynced\")].status}' | grep -q True"

echo ""
echo "${BLUE}4. Composition Functions${NC}"
echo "-----------------------"

# Test 14: Patch and Transform function
if kubectl get function function-patch-and-transform > /dev/null 2>&1; then
    run_test "Patch and Transform function installed" \
        "kubectl get function function-patch-and-transform -o jsonpath='{.status.conditions[?(@.type==\"Installed\")].status}' | grep -q True"
    
    run_test "Patch and Transform function healthy" \
        "kubectl get function function-patch-and-transform -o jsonpath='{.status.conditions[?(@.type==\"Healthy\")].status}' | grep -q True"
fi

# Test 15: Auto Ready function
if kubectl get function function-auto-ready > /dev/null 2>&1; then
    run_test "Auto Ready function installed" \
        "kubectl get function function-auto-ready -o jsonpath='{.status.conditions[?(@.type==\"Installed\")].status}' | grep -q True"
    
    run_test "Auto Ready function healthy" \
        "kubectl get function function-auto-ready -o jsonpath='{.status.conditions[?(@.type==\"Healthy\")].status}' | grep -q True"
fi

echo ""
echo "${BLUE}5. Compositions${NC}"
echo "--------------"

# Test 16: XRD for S3 buckets
if kubectl get xrd xbuckets.storage.platform.io > /dev/null 2>&1; then
    run_test "S3 Bucket XRD exists" \
        "kubectl get xrd xbuckets.storage.platform.io"
    
    run_test "S3 Bucket XRD established" \
        "kubectl get xrd xbuckets.storage.platform.io -o jsonpath='{.status.conditions[?(@.type==\"Established\")].status}' | grep -q True"
fi

# Test 17: Composition for S3 buckets
if kubectl get composition xbuckets.aws.storage.platform.io > /dev/null 2>&1; then
    run_test "S3 Bucket Composition exists" \
        "kubectl get composition xbuckets.aws.storage.platform.io"
fi

echo ""
echo "${BLUE}6. CRDs${NC}"
echo "-------"

# Test 18: Check CRDs are installed
run_test "Crossplane CRDs installed" \
    "kubectl get crd | grep -q crossplane.io"

run_test "AWS Provider CRDs installed" \
    "kubectl get crd | grep -q aws.upbound.io"

echo ""
echo "${BLUE}7. Connectivity Tests${NC}"
echo "--------------------"

# Test 19: LocalStack connectivity (dev environment)
if kubectl get configmap cluster-vars -n flux-system -o jsonpath='{.data.AWS_ENDPOINT_URL}' | grep -q localstack; then
    echo -e "${YELLOW}Running in development mode with LocalStack${NC}"
    
    run_test "LocalStack service exists" \
        "kubectl get service localstack -n localstack"
    
    # Test LocalStack connectivity from Crossplane pod
    if kubectl get pod -n crossplane-system -l app=crossplane -o name | head -1 > /dev/null 2>&1; then
        POD_NAME=$(kubectl get pod -n crossplane-system -l app=crossplane -o name | head -1 | cut -d'/' -f2)
        run_test "LocalStack reachable from Crossplane" \
            "kubectl exec -n crossplane-system $POD_NAME -- curl -s http://localstack.localstack.svc.cluster.local:4566/_localstack/health | grep -q '\"services\"'"
    fi
fi

echo ""
echo "${BLUE}8. Functional Test${NC}"
echo "-----------------"

# Test 20: Create a test S3 bucket
TEST_BUCKET_NAME="crossplane-test-bucket-$(date +%s)"

echo -e "${YELLOW}Creating test S3 bucket: $TEST_BUCKET_NAME${NC}"

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: $TEST_BUCKET_NAME
  labels:
    testing: crossplane
spec:
  forProvider:
    region: us-east-1
    tags:
      Test: "true"
      CreatedBy: "test-script"
  providerConfigRef:
    name: default
EOF

if [ $? -eq 0 ]; then
    echo -e "Test bucket created: ${GREEN}✓${NC}"
    ((TESTS_PASSED++))
    
    # Wait for bucket to be ready (up to 30 seconds)
    echo -n "Waiting for bucket to be ready"
    for i in {1..30}; do
        if check_resource_status "bucket.s3.aws.upbound.io" "$TEST_BUCKET_NAME"; then
            echo -e " ${GREEN}✓${NC}"
            ((TESTS_PASSED++))
            break
        fi
        echo -n "."
        sleep 1
    done
    
    if ! check_resource_status "bucket.s3.aws.upbound.io" "$TEST_BUCKET_NAME"; then
        echo -e " ${RED}✗${NC} (timeout)"
        ((TESTS_FAILED++))
    fi
    
    # Clean up test bucket
    echo -n "Cleaning up test bucket..."
    kubectl delete bucket "$TEST_BUCKET_NAME" > /dev/null 2>&1
    echo -e " ${GREEN}✓${NC}"
else
    echo -e "Failed to create test bucket: ${RED}✗${NC}"
    ((TESTS_FAILED++))
fi

echo ""
echo "${BLUE}9. Metrics & Monitoring${NC}"
echo "----------------------"

# Test 21: Metrics endpoint
if kubectl get pod -n crossplane-system -l app=crossplane -o name | head -1 > /dev/null 2>&1; then
    POD_NAME=$(kubectl get pod -n crossplane-system -l app=crossplane -o name | head -1 | cut -d'/' -f2)
    run_test "Metrics endpoint accessible" \
        "kubectl exec -n crossplane-system $POD_NAME -- curl -s localhost:8080/metrics | grep -q controller_runtime_reconcile"
fi

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC} Crossplane is properly installed and configured."
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some tests failed.${NC} Please check the configuration and try again."
    echo ""
    echo "Debugging tips:"
    echo "  1. Check Crossplane logs: kubectl logs -n crossplane-system deployment/crossplane"
    echo "  2. Check provider logs: kubectl logs -n crossplane-system -l pkg.crossplane.io/provider"
    echo "  3. Check External Secrets: kubectl get externalsecrets -A"
    echo "  4. Verify LocalStack is running: kubectl get pods -n localstack"
    echo "  5. Run init script: make init-aws-secrets"
    exit 1
fi