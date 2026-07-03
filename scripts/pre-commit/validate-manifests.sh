#!/usr/bin/env bash

# This script downloads the Flux OpenAPI schemas, then it validates the
# Flux custom resources and the kustomize overlays using kubeconform.
# This script is meant to be run locally and in CI before the changes
# are merged on the main branch that's synced by Flux.

# Based on: https://github.com/fluxcd/flux2-kustomize-helm-example/blob/main/scripts/validate.sh

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
    local missing_tools=()

    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi

    if ! command -v kubeconform &> /dev/null; then
        missing_tools+=("kubeconform")
    fi

    if ! command -v kustomize &> /dev/null; then
        missing_tools+=("kustomize")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo_error "Missing required tools: ${missing_tools[*]}"
        echo_info "Install with:"
        echo "  brew install yq kubeconform kustomize"
        echo "  or"
        echo "  https://kubectl.docs.kubernetes.io/installation/kustomize/"
        echo "  https://github.com/yannh/kubeconform"
        exit 1
    fi

    if command -v flux &> /dev/null; then
        FLUX_AVAILABLE=true
    else
        FLUX_AVAILABLE=false
        echo_warn "flux CLI not found; skipping flux build kustomization --dry-run checks"
    fi
}

# Download Flux CRD schemas
download_flux_schemas() {
    local schema_dir="/tmp/flux-crd-schemas/master-standalone-strict"

    if [ -d "$schema_dir" ]; then
        echo_info "Flux schemas already downloaded"
        return 0
    fi

    echo_info "Downloading Flux OpenAPI schemas"
    mkdir -p "$schema_dir"

    if ! curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict; then
        echo_error "Failed to download Flux CRD schemas"
        exit 1
    fi

    echo_info "Flux schemas downloaded successfully"
}

# Validate YAML syntax
validate_yaml_syntax() {
    echo_info "Validating YAML syntax"
    local error_count=0

    while IFS= read -r -d $'\0' file; do
        if ! yq e 'true' "$file" > /dev/null 2>&1; then
            echo_error "Invalid YAML syntax in $file"
            ((error_count++))
        fi
    done < <(find . -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | grep -zv '.sops.ya\?ml$')

    if [ $error_count -gt 0 ]; then
        echo_error "Found $error_count YAML syntax errors"
        exit 1
    fi

    echo_info "All YAML files have valid syntax"
}

# Validate cluster manifests
validate_cluster_manifests() {
    echo_info "Validating cluster manifests"
    local kubeconform_flags=("-skip" "Secret")
    local kubeconform_config=("-strict" "-ignore-missing-schemas" "-schema-location" "default" "-schema-location" "/tmp/flux-crd-schemas" "-verbose")
    local error_count=0

    while IFS= read -r -d $'\0' file; do
        echo_info "Validating $file"
        if ! kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" "${file}"; then
            ((error_count++))
        fi
    done < <(find ./clusters -maxdepth 2 -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

    if [ $error_count -gt 0 ]; then
        echo_error "Found $error_count invalid cluster manifests"
        exit 1
    fi

    echo_info "All cluster manifests are valid"
}

# Validate base app manifests
validate_apps_base_manifests() {
    echo_info "Validating apps/base manifests"
    local kubeconform_flags=("-skip" "Secret")
    local kubeconform_config=("-strict" "-ignore-missing-schemas" "-schema-location" "default" "-schema-location" "/tmp/flux-crd-schemas" "-verbose")
    local error_count=0

    while IFS= read -r -d $'\0' file; do
        echo_info "Validating $file"
        if ! kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" "${file}"; then
            ((error_count++))
        fi
    done < <(find ./apps/base -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

    if [ $error_count -gt 0 ]; then
        echo_error "Found $error_count invalid apps/base manifests"
        exit 1
    fi

    echo_info "All apps/base manifests are valid"
}

# Validate Flux Kustomization rendering when flux CLI is available
validate_flux_kustomizations() {
    if [ "${FLUX_AVAILABLE:-false}" != true ]; then
        return 0
    fi

    echo_info "Validating Flux kustomizations with flux build --dry-run"
    local error_count=0

    while IFS= read -r -d $'\0' file; do
        local name
        name=$(yq e 'select(.kind == "Kustomization") | .metadata.name' "$file" 2>/dev/null || echo "")
        local path
        path=$(yq e 'select(.kind == "Kustomization") | .spec.path' "$file" 2>/dev/null || echo "")

        if [ -z "$name" ] || [ -z "$path" ] || [ "$name" = "null" ] || [ "$path" = "null" ]; then
            echo_warn "Skipping invalid kustomization file (missing metadata.name/spec.path): $file"
            continue
        fi

        echo_info "flux build kustomization --dry-run ${name} (${path})"
        if ! flux build kustomization "$name" --path clusters/stages/dev/clusters/services-amer --kustomization-file "$file" --dry-run >/dev/null; then
            echo_error "flux build failed for $file"
            ((error_count++))
        fi
    done < <(find ./base/services -maxdepth 1 -type f -name '*.yaml' -print0)

    if [ $error_count -gt 0 ]; then
        echo_error "Found $error_count flux kustomization build failures"
        exit 1
    fi

    echo_info "All Flux kustomizations build successfully"
}

# Main execution
main() {
    echo_info "Starting Flux manifest validation"

    check_prerequisites
    download_flux_schemas
    validate_yaml_syntax
    validate_cluster_manifests
    validate_apps_base_manifests
    validate_flux_kustomizations

    echo_info "✓ All manifest validations passed"
}

main "$@"
