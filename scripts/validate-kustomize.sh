#!/usr/bin/env bash

# This script validates all kustomization.yaml files by attempting to build them
# and checking the resulting manifests with kubeconform

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

# Check for required tools
check_prerequisites() {
    if ! command -v kustomize &> /dev/null; then
        echo_error "kustomize is not installed"
        echo_info "Install with: brew install kustomize"
        echo_info "or: https://kubectl.docs.kubernetes.io/installation/kustomize/"
        exit 1
    fi
    
    if ! command -v kubeconform &> /dev/null; then
        echo_error "kubeconform is not installed"
        echo_info "Install with: brew install kubeconform"
        echo_info "or: https://github.com/yannh/kubeconform"
        exit 1
    fi
}

# Kustomize build options (mirror kustomize-controller)
KUSTOMIZE_FLAGS=("--load-restrictor=LoadRestrictionsNone")
KUSTOMIZE_CONFIG="kustomization.yaml"

# Kubeconform options
KUBECONFORM_FLAGS=("-skip" "Secret")
KUBECONFORM_CONFIG=("-strict" "-ignore-missing-schemas" "-schema-location" "default" "-schema-location" "/tmp/flux-crd-schemas" "-verbose")

# Download Flux CRD schemas if not present
download_flux_schemas() {
    local schema_dir="/tmp/flux-crd-schemas/master-standalone-strict"
    
    if [ -d "$schema_dir" ]; then
        return 0
    fi
    
    echo_info "Downloading Flux OpenAPI schemas"
    mkdir -p "$schema_dir"
    
    if ! curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict 2>/dev/null; then
        echo_warn "Failed to download Flux CRD schemas, continuing without them"
    fi
}

# Validate a single kustomization
validate_kustomization() {
    local kustomization_dir=$1
    local dir_name=$(basename "$kustomization_dir")
    
    echo_info "Validating kustomization: ${kustomization_dir}"
    
    # Try to build the kustomization
    local build_output
    if ! build_output=$(kustomize build "${kustomization_dir}" "${KUSTOMIZE_FLAGS[@]}" 2>&1); then
        echo_error "Failed to build kustomization in ${kustomization_dir}"
        echo "$build_output"
        return 1
    fi
    
    # Validate the built manifests with kubeconform
    if ! echo "$build_output" | kubeconform "${KUBECONFORM_FLAGS[@]}" "${KUBECONFORM_CONFIG[@]}" 2>&1; then
        echo_error "Validation failed for kustomization in ${kustomization_dir}"
        return 1
    fi
    
    echo_info "✓ Kustomization ${kustomization_dir} is valid"
    return 0
}

# Main execution
main() {
    echo_info "Starting Kustomize overlay validation"
    
    check_prerequisites
    download_flux_schemas
    
    local error_count=0
    local total_count=0
    
    # Find all kustomization.yaml files
    while IFS= read -r -d $'\0' file; do
        ((total_count++))
        local dir="${file%/$KUSTOMIZE_CONFIG}"
        
        if ! validate_kustomization "$dir"; then
            ((error_count++))
        fi
    done < <(find . -type f -name "$KUSTOMIZE_CONFIG" -print0 | grep -zv '.git/')
    
    echo ""
    echo_info "Kustomize validation complete"
    echo "  Total kustomizations: $total_count"
    echo "  Errors: $error_count"
    
    if [ $error_count -gt 0 ]; then
        echo_error "Found $error_count invalid kustomizations"
        exit 1
    fi
    
    echo_info "✓ All kustomizations are valid"
}

main "$@"
