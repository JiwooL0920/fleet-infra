#!/usr/bin/env bash

# This script checks that Flux CRDs use current API versions
# and warns about deprecated versions that should be upgraded

set -o errexit
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}INFO${NC} - $1"
}

echo_error() {
    echo -e "${RED}ERROR${NC} - $1"
}

echo_warn() {
    echo -e "${YELLOW}WARN${NC} - $1"
}

# Track errors and warnings
ERROR_COUNT=0
WARN_COUNT=0

# Check if an API version is current
is_current_version() {
    local apiVersion=$1
    local kind=$2
    
    case "$kind" in
        "Kustomization")
            [[ "$apiVersion" == "kustomize.toolkit.fluxcd.io/v1" ]]
            ;;
        "HelmRelease")
            [[ "$apiVersion" == "helm.toolkit.fluxcd.io/v2" ]]
            ;;
        "GitRepository"|"HelmRepository"|"HelmChart")
            [[ "$apiVersion" == "source.toolkit.fluxcd.io/v1" ]]
            ;;
        "OCIRepository"|"Bucket")
            [[ "$apiVersion" == "source.toolkit.fluxcd.io/v1beta2" ]]
            ;;
        *)
            return 0  # Unknown kind, assume OK
            ;;
    esac
}

# Get the current version for a kind
get_current_version() {
    local kind=$1
    
    case "$kind" in
        "Kustomization") echo "kustomize.toolkit.fluxcd.io/v1" ;;
        "HelmRelease") echo "helm.toolkit.fluxcd.io/v2" ;;
        "GitRepository"|"HelmRepository"|"HelmChart") echo "source.toolkit.fluxcd.io/v1" ;;
        "OCIRepository"|"Bucket") echo "source.toolkit.fluxcd.io/v1beta2" ;;
        *) echo "" ;;
    esac
}

# Check if version is deprecated
is_deprecated() {
    local apiVersion=$1
    
    case "$apiVersion" in
        "kustomize.toolkit.fluxcd.io/v1beta1"|"kustomize.toolkit.fluxcd.io/v1beta2")
            echo "kustomize.toolkit.fluxcd.io/v1"
            return 0
            ;;
        "helm.toolkit.fluxcd.io/v2beta1"|"helm.toolkit.fluxcd.io/v2beta2")
            echo "helm.toolkit.fluxcd.io/v2"
            return 0
            ;;
        "source.toolkit.fluxcd.io/v1beta1")
            echo "source.toolkit.fluxcd.io/v1"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_file() {
    local file=$1
    local apiVersion kind
    
    # Extract apiVersion and kind
    if command -v yq &> /dev/null; then
        apiVersion=$(yq e '.apiVersion' "$file" 2>/dev/null || echo "")
        kind=$(yq e '.kind' "$file" 2>/dev/null || echo "")
    else
        apiVersion=$(grep -E '^apiVersion:' "$file" | head -1 | awk '{print $2}' || echo "")
        kind=$(grep -E '^kind:' "$file" | head -1 | awk '{print $2}' || echo "")
    fi
    
    # Skip if not a Flux resource
    if [[ ! "$apiVersion" =~ toolkit.fluxcd.io ]]; then
        return 0
    fi
    
    # Check if using deprecated version
    local upgrade_to
    if upgrade_to=$(is_deprecated "$apiVersion" 2>/dev/null); then
        echo_warn "Deprecated API version in $file"
        echo "  Found: $apiVersion"
        echo "  Upgrade to: $upgrade_to"
        ((WARN_COUNT++))
    fi
    
    # Check if using current version for known kinds
    local current_version
    current_version=$(get_current_version "$kind")
    if [[ -n "$current_version" && "$apiVersion" != "$current_version" ]]; then
        # Only error if it's a known deprecated version
        if is_deprecated "$apiVersion" &>/dev/null; then
            echo_error "Outdated API version for $kind in $file"
            echo "  Found: $apiVersion"
            echo "  Current: $current_version"
            ((ERROR_COUNT++))
        fi
    fi
}

# Main execution
main() {
    echo_info "Checking Flux API versions"
    
    # Find all YAML files containing Flux CRDs
    while IFS= read -r file; do
        [[ -n "$file" ]] && check_file "$file"
    done < <(find . -type f \( -name '*.yaml' -o -name '*.yml' \) \
        -exec grep -l 'toolkit.fluxcd.io' {} \; 2>/dev/null)
    
    echo ""
    echo_info "API version check complete"
    echo "  Errors: $ERROR_COUNT"
    echo "  Warnings: $WARN_COUNT"
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo_error "Found $ERROR_COUNT API version errors"
        echo "Please upgrade deprecated Flux API versions"
        echo "See: https://fluxcd.io/flux/migration/"
        exit 1
    fi
    
    if [ $WARN_COUNT -gt 0 ]; then
        echo_warn "Found $WARN_COUNT deprecated API versions"
        echo "Consider upgrading to current versions"
    else
        echo_info "✓ All Flux API versions are current"
    fi
}

main "$@"
