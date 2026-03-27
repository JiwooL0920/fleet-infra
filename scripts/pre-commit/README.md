# Pre-commit Validation Scripts

This directory contains validation scripts used by pre-commit hooks to ensure code quality and correctness in the FluxCD GitOps repository.

## Scripts

### validate-manifests.sh
Validates Kubernetes and Flux manifests using kubeconform.

**What it does:**
- Downloads latest Flux CRD schemas
- Validates YAML syntax with yq
- Validates manifests against Kubernetes and Flux schemas
- Skips Secrets (may contain SOPS fields)

**Usage:**
```bash
./scripts/pre-commit/validate-manifests.sh
```

### check-flux-versions.sh
Checks Flux CRD API versions and warns about deprecated versions.

**What it checks:**
- Current versions: v1 (Kustomization, GitRepository, HelmRepository, HelmChart), v2 (HelmRelease)
- Deprecated: v1beta1, v1beta2, v2beta1, v2beta2

**Usage:**
```bash
./scripts/pre-commit/check-flux-versions.sh
```

### validate-kustomize.sh
Validates all Kustomize overlays can be built successfully.

**What it does:**
- Finds all kustomization.yaml files
- Runs kustomize build with Flux controller flags
- Validates generated manifests with kubeconform

**Usage:**
```bash
./scripts/pre-commit/validate-kustomize.sh
```

## Integration

These scripts are called automatically by pre-commit hooks defined in `.pre-commit-config.yaml`.

They can also be run manually or via Makefile targets:
```bash
make validate-manifests
make validate-flux
make validate-kustomize
make validate-all
```

## Requirements

- kubeconform
- kustomize
- yq
- curl

Install with:
```bash
brew install kubeconform kustomize yq
```

## Exit Codes

- `0`: All validations passed
- `1`: Validation errors found
- `2`: Missing prerequisites

## See Also

- [Pre-commit Hooks Documentation](../../docs/PRE_COMMIT_HOOKS.md)
- [FluxCD Validation Guide](https://fluxcd.io/flux/guides/repository-structure/)
