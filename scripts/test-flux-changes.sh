#!/bin/bash

set -e

echo "🔍 Testing Flux changes locally..."

# 1. Check Flux prerequisites
echo "1. Checking Flux prerequisites..."
flux check --pre

# 2. Validate all kustomizations
echo "2. Validating kustomizations..."
find . -name "kustomization.yaml" -exec dirname {} \; | while read dir; do
    echo "  Testing: $dir"
    kustomize build "$dir" > /dev/null || echo "❌ Failed: $dir"
done

# 3. Check HelmRelease resources
echo "3. Checking HelmRelease resources..."
find . -name "helmrelease.yaml" -o -name "*helmrelease*.yaml" | while read file; do
    echo "  Validating: $file"
    kubectl apply --dry-run=client -f "$file" || echo "❌ Failed: $file"
done

# 4. Check for common issues
echo "4. Checking for common issues..."

# Check for duplicate resource names
echo "  Checking for duplicate resource names..."
find . -name "*.yaml" -exec grep -l "kind:" {} \; | xargs grep -h "name:" | sort | uniq -d

# Check for missing namespaces
echo "  Checking for resources without namespaces..."
find . -name "*.yaml" -exec grep -L "namespace:" {} \; | grep -v kustomization

echo "✅ Local testing complete!"
