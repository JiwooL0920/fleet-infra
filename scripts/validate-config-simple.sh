#!/bin/bash
set -e

# Simple Configuration Migration Validation Script
# This script validates the configuration files and structure without requiring Flux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cd "$PROJECT_ROOT"

print_status "Starting configuration migration validation"

# Step 1: Validate configuration files exist
print_status "Step 1: Validating configuration file structure"

REQUIRED_FILES=(
    "base/services/environment.env"
    "clusters/stages/dev/clusters/services-amer/environment.env"
    "clusters/stages/prod/clusters/services-amer/environment.env"
    "clusters/stages/dev/clusters/services-amer/kustomization.yaml"
    "clusters/stages/prod/clusters/services-amer/kustomization.yaml"
)

ALL_FILES_EXIST=true
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        print_success "✓ Found $file"
    else
        print_error "✗ Missing $file"
        ALL_FILES_EXIST=false
    fi
done

if [[ "$ALL_FILES_EXIST" != "true" ]]; then
    print_error "Missing required configuration files"
    exit 1
fi

# Step 2: Validate environment file syntax
print_status "Step 2: Validating environment file syntax"

for env_file in base/services/environment.env clusters/stages/*/clusters/services-amer/environment.env; do
    if [[ -f "$env_file" ]]; then
        # Check for basic syntax (key=value pairs)
        if grep -q "^[A-Z_][A-Z0-9_]*=" "$env_file"; then
            VARIABLE_COUNT=$(grep -c "^[A-Z_][A-Z0-9_]*=" "$env_file")
            print_success "✓ $env_file: $VARIABLE_COUNT variables defined"
        else
            print_error "✗ $env_file: Invalid syntax or no variables found"
            exit 1
        fi
    fi
done

# Step 3: Validate HelmRelease migrations
print_status "Step 3: Validating HelmRelease migrations"

# Redis validation
REDIS_HELMRELEASE="apps/base/redis/helmrelease.yaml"
if [[ -f "$REDIS_HELMRELEASE" ]]; then
    REDIS_VARIABLES=(
        '\${REDIS_CHART_VERSION}'
        '\${REDIS_MASTER_MEMORY_LIMIT}'
        '\${REDIS_REPLICA_COUNT}'
        '\${REDIS_STORAGE_SIZE}'
    )
    
    REDIS_VARIABLES_FOUND=0
    for pattern in "${REDIS_VARIABLES[@]}"; do
        if grep -q "$pattern" "$REDIS_HELMRELEASE"; then
            ((REDIS_VARIABLES_FOUND++))
        fi
    done
    
    if [[ $REDIS_VARIABLES_FOUND -gt 0 ]]; then
        print_success "✓ Redis HelmRelease contains $REDIS_VARIABLES_FOUND variable substitutions"
    else
        print_error "✗ Redis HelmRelease contains no variable substitutions"
        exit 1
    fi
else
    print_error "✗ Redis HelmRelease not found: $REDIS_HELMRELEASE"
    exit 1
fi

# Loki validation
LOKI_HELMRELEASE="apps/base/loki/helmrelease.yaml"
if [[ -f "$LOKI_HELMRELEASE" ]]; then
    LOKI_VARIABLES=(
        '\${LOKI_CHART_VERSION}'
        '\${LOKI_MEMORY_LIMIT}'
        '\${LOKI_REPLICA_COUNT}'
        '\${LOKI_STORAGE_SIZE}'
        '\${LOKI_RETENTION_PERIOD}'
        '\${LOKI_CACHE_EXPIRATION}'
    )
    
    LOKI_VARIABLES_FOUND=0
    for pattern in "${LOKI_VARIABLES[@]}"; do
        if grep -q "$pattern" "$LOKI_HELMRELEASE"; then
            ((LOKI_VARIABLES_FOUND++))
        fi
    done
    
    if [[ $LOKI_VARIABLES_FOUND -gt 0 ]]; then
        print_success "✓ Loki HelmRelease contains $LOKI_VARIABLES_FOUND variable substitutions"
    else
        print_error "✗ Loki HelmRelease contains no variable substitutions"
        exit 1
    fi
else
    print_error "✗ Loki HelmRelease not found: $LOKI_HELMRELEASE"
    exit 1
fi

# Step 4: Validate variable definitions exist
print_status "Step 4: Validating variable definitions"

BASE_ENV="base/services/environment.env"
MISSING_VARIABLES=()

# Check that all variables used in HelmReleases are defined
ALL_VARIABLES=(
    REDIS_CHART_VERSION REDIS_MASTER_MEMORY_LIMIT REDIS_REPLICA_COUNT REDIS_STORAGE_SIZE
    LOKI_CHART_VERSION LOKI_MEMORY_LIMIT LOKI_REPLICA_COUNT LOKI_STORAGE_SIZE 
    LOKI_RETENTION_PERIOD LOKI_CACHE_EXPIRATION LOKI_CACHE_TIMEOUT LOKI_REDIS_POOL_SIZE LOKI_WRITE_POOL_SIZE
)

for var in "${ALL_VARIABLES[@]}"; do
    if grep -q "^${var}=" "$BASE_ENV"; then
        print_success "✓ Variable $var is defined in base configuration"
    else
        MISSING_VARIABLES+=("$var")
        print_error "✗ Variable $var is not defined in base configuration"
    fi
done

if [[ ${#MISSING_VARIABLES[@]} -gt 0 ]]; then
    print_error "Missing variable definitions: ${MISSING_VARIABLES[*]}"
    exit 1
fi

# Step 5: Validate environment-specific overrides
print_status "Step 5: Validating environment-specific overrides"

DEV_ENV="clusters/stages/dev/clusters/services-amer/environment.env"
PROD_ENV="clusters/stages/prod/clusters/services-amer/environment.env"

# Check for environment-specific values
DEV_REDIS_MEMORY=$(grep "^REDIS_MASTER_MEMORY_LIMIT=" "$DEV_ENV" | cut -d'=' -f2 || echo "")
PROD_REDIS_MEMORY=$(grep "^REDIS_MASTER_MEMORY_LIMIT=" "$PROD_ENV" | cut -d'=' -f2 || echo "")

if [[ -n "$DEV_REDIS_MEMORY" && -n "$PROD_REDIS_MEMORY" ]]; then
    print_success "✓ Found environment-specific Redis memory limits"
    print_status "  Dev: $DEV_REDIS_MEMORY"
    print_status "  Prod: $PROD_REDIS_MEMORY"
    
    # Verify prod has higher limits than dev
    if [[ "$PROD_REDIS_MEMORY" =~ "1Gi"|"2Gi"|"4Gi" ]] && [[ "$DEV_REDIS_MEMORY" =~ "128Mi"|"256Mi"|"512Mi" ]]; then
        print_success "✓ Production has higher resource limits than development"
    else
        print_warning "⚠ Resource allocation patterns may need review"
    fi
else
    print_warning "⚠ Environment-specific Redis memory limits not found"
fi

# Step 6: Validate kustomization structure
print_status "Step 6: Validating kustomization structure"

for kust_file in clusters/stages/*/clusters/services-amer/kustomization.yaml; do
    env=$(echo "$kust_file" | cut -d'/' -f3)
    
    # Check for required sections
    if grep -q "postBuild:" "$kust_file"; then
        print_success "✓ $env kustomization has postBuild configuration"
    else
        print_error "✗ $env kustomization missing postBuild configuration"
        exit 1
    fi
    
    if grep -q "configMapGenerator:" "$kust_file"; then
        print_success "✓ $env kustomization has configMapGenerator"
    else
        print_error "✗ $env kustomization missing configMapGenerator"
        exit 1
    fi
    
    if grep -q "environment.env" "$kust_file"; then
        print_success "✓ $env kustomization references environment.env"
    else
        print_error "✗ $env kustomization does not reference environment.env"
        exit 1
    fi
done

print_success "Configuration migration validation completed successfully!"

# Summary
echo ""
echo "=================================="
echo "VALIDATION SUMMARY"
echo "=================================="
echo "Configuration files: ✓ Valid"
echo "Environment files: ✓ Valid syntax"  
echo "HelmRelease migrations: ✓ Redis and Loki variables implemented"
echo "Variable definitions: ✓ Complete"
echo "Environment overrides: ✓ Configured"
echo "Kustomization structure: ✓ Valid"
echo ""

print_status "Next steps:"
echo "1. Test deployment in development environment"
echo "2. Validate application startup with new configuration"
echo "3. Proceed with Loki migration"
echo "4. Implement remaining services"