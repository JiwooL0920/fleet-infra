# Pre-commit Hooks for FluxCD GitOps Repository

This document explains the pre-commit hooks configured for this repository and how to use them.

## Overview

Pre-commit hooks automatically validate your changes before each commit, catching issues early and ensuring code quality. Our hooks are specifically tailored for FluxCD GitOps workflows.

## Prerequisites

### Required Tools

Install the following tools before using pre-commit hooks:

```bash
# Install pre-commit
brew install pre-commit
# or
pip install pre-commit

# Install validation tools
brew install kubeconform kustomize yq

# Install linters
brew install yamllint shellcheck markdownlint-cli

# Install secret scanner
brew install detect-secrets
```

### Tool Versions

- pre-commit: >= 3.0.0
- kubeconform: >= 0.6.0
- kustomize: >= 5.0.0
- yq: >= 4.0.0
- yamllint: >= 1.35.0
- shellcheck: >= 0.9.0
- markdownlint-cli: >= 0.40.0
- detect-secrets: >= 1.4.0

## Installation

1. Install pre-commit hooks:
   ```bash
   pre-commit install
   ```

2. Create secrets baseline:
   ```bash
   detect-secrets scan > .secrets.baseline
   ```

3. (Optional) Install commit-msg hook:
   ```bash
   pre-commit install --hook-type commit-msg
   ```

## Hooks Explained

### General File Checks

#### check-added-large-files
Prevents committing files larger than 1MB. Large files should be stored in Git LFS or external storage.

**Skip for specific files:**
```bash
git commit --no-verify  # Skip all hooks
```

#### end-of-file-fixer
Ensures files end with a newline character (POSIX standard).

**Excluded:** SOPS-encrypted files (`*.sops.yaml`)

#### trailing-whitespace
Removes trailing whitespace from all files.

**Special handling:** Preserves Markdown hard line breaks

#### check-yaml
Validates YAML syntax for all `.yaml` and `.yml` files.

**Flags:**
- `--allow-multiple-documents`: Supports multi-doc YAML files
- `--unsafe`: Allows custom YAML tags

**Excluded:** Helm chart templates

#### check-merge-conflict
Detects unresolved merge conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).

#### check-symlinks
Ensures symlinks point to existing files.

#### no-commit-to-branch
Prevents direct commits to protected branches (`main`, `master`).

**Override when needed:**
```bash
git commit --no-verify -m "hotfix: critical production fix"
```

#### detect-aws-credentials
Scans for AWS access keys and secret keys.

**Flags:** `--allow-missing-credentials` (won't fail if no AWS config exists)

#### detect-private-key
Detects private SSH/TLS keys in committed files.

#### check-case-conflict
Prevents filename conflicts on case-insensitive filesystems (macOS, Windows).

### YAML Linting

#### yamllint
Enforces consistent YAML formatting and style.

**Configuration:** `.yamllint` (inline) or `.yamllint.yaml`

**Rules:**
- Line length: 120 characters (warning)
- No document-start markers required
- Truthy values: `true`, `false`, `on`, `off`

**Excluded:** Helm templates

### Flux-Specific Validation

#### kubeconform (validate-manifests.sh)
Validates Kubernetes and Flux manifests against OpenAPI schemas.

**What it does:**
1. Downloads latest Flux CRD schemas
2. Validates YAML syntax with `yq`
3. Validates cluster manifests with `kubeconform`
4. Checks against both Kubernetes and Flux schemas

**Skipped:** Kubernetes Secrets (may contain SOPS fields)

**Run manually:**
```bash
./scripts/pre-commit/validate-manifests.sh
```

#### flux-check-versions (check-flux-versions.sh)
Ensures Flux CRDs use current API versions.

**Current versions checked:**
- `Kustomization`: `kustomize.toolkit.fluxcd.io/v1`
- `HelmRelease`: `helm.toolkit.fluxcd.io/v2`
- `GitRepository`: `source.toolkit.fluxcd.io/v1`
- `HelmRepository`: `source.toolkit.fluxcd.io/v1`
- `OCIRepository`: `source.toolkit.fluxcd.io/v1beta2`

**Deprecated versions warned:**
- `kustomize.toolkit.fluxcd.io/v1beta1` → `v1`
- `kustomize.toolkit.fluxcd.io/v1beta2` → `v1`
- `helm.toolkit.fluxcd.io/v2beta1` → `v2`
- `helm.toolkit.fluxcd.io/v2beta2` → `v2`

**Run manually:**
```bash
./scripts/pre-commit/check-flux-versions.sh
```

#### kustomize-build (validate-kustomize.sh)
Validates all Kustomize overlays can be built successfully.

**What it does:**
1. Finds all `kustomization.yaml` files
2. Runs `kustomize build` with Flux controller flags
3. Validates generated manifests with `kubeconform`

**Flags:** `--load-restrictor=LoadRestrictionsNone` (mirrors kustomize-controller)

**Run manually:**
```bash
./scripts/pre-commit/validate-kustomize.sh
```

### Security Scanning

#### detect-secrets
Scans for hardcoded secrets, API keys, and credentials.

**Configuration:** `.secrets.baseline`

**Excluded:**
- SOPS-encrypted files (`*.sops.yaml`)
- Known environment files (`secrets.env`)

**Update baseline:**
```bash
detect-secrets scan --baseline .secrets.baseline
```

**Audit findings:**
```bash
detect-secrets audit .secrets.baseline
```

### Code Quality

#### markdownlint
Lints Markdown files for consistent formatting.

**Configuration:** `.markdownlint.yaml`

**Key rules:**
- Line length: 120 characters
- Inline HTML allowed
- ATX-style headings (`#`) preferred

#### shellcheck
Lints shell scripts for common errors and best practices.

**Severity:** Warning and above

**Run manually:**
```bash
shellcheck scripts/*.sh
```

#### forbid-tabs
Prevents tab characters in YAML files (except Makefiles).

## Usage

### Running Pre-commit Hooks

**Automatic:** Hooks run automatically on `git commit`

**Manual (all files):**
```bash
pre-commit run --all-files
```

**Manual (specific hook):**
```bash
pre-commit run kubeconform --all-files
pre-commit run yamllint --all-files
```

**Manual (staged files only):**
```bash
pre-commit run
```

### Skipping Hooks

**Skip all hooks:**
```bash
git commit --no-verify -m "commit message"
```

**Skip specific hook:**
Set `SKIP` environment variable:
```bash
SKIP=kubeconform git commit -m "skip kubeconform validation"
SKIP=detect-secrets,shellcheck git commit -m "skip multiple hooks"
```

### Updating Hooks

**Update to latest versions:**
```bash
pre-commit autoupdate
```

**Update specific hook:**
```bash
pre-commit autoupdate --repo https://github.com/pre-commit/pre-commit-hooks
```

## Troubleshooting

### Hook Fails: Tool Not Found

**Error:** `kubeconform: command not found`

**Solution:**
```bash
brew install kubeconform
# or download from https://github.com/yannh/kubeconform/releases
```

### Hook Fails: Permission Denied

**Error:** `Permission denied: ./scripts/validate-manifests.sh`

**Solution:**
```bash
chmod +x scripts/*.sh
```

### YAML Validation Fails

**Error:** `invalid YAML syntax`

**Debug:**
```bash
yq e 'true' path/to/file.yaml
yamllint path/to/file.yaml
```

### Kustomize Build Fails

**Error:** `failed to build kustomization`

**Debug:**
```bash
kustomize build path/to/overlay --load-restrictor=LoadRestrictionsNone
```

### Secrets Baseline False Positives

**Issue:** detect-secrets flags non-secrets

**Solution:**
```bash
# Audit and mark as false positive
detect-secrets audit .secrets.baseline

# Or regenerate baseline
detect-secrets scan --baseline .secrets.baseline
```

### Slow Hook Execution

**Issue:** Hooks take too long

**Solutions:**
1. Run only on changed files (default behavior)
2. Disable expensive hooks locally:
   ```bash
   SKIP=kubeconform,kustomize-build git commit -m "message"
   ```
3. Use `fail_fast: true` in `.pre-commit-config.yaml`

### Hook Version Conflicts

**Issue:** Hook versions incompatible

**Solution:**
```bash
# Clean cache and reinstall
pre-commit clean
pre-commit install --install-hooks
```

## CI Integration

These hooks should also run in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run pre-commit
  uses: pre-commit/action@v3.0.0
```

Or manually:
```bash
pre-commit run --all-files
```

## Customization

### Disabling a Hook

Edit `.pre-commit-config.yaml`:

```yaml
- id: hook-name
  # Comment out or remove the hook
```

### Adding New Hooks

Edit `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/owner/repo
    rev: v1.0.0
    hooks:
      - id: new-hook
        args: [--flag]
```

Then run:
```bash
pre-commit install --install-hooks
```

### Excluding Files

Global exclusions in `.pre-commit-config.yaml`:

```yaml
exclude: |
  (?x)^(
      path/to/exclude/.*|
      .*\.generated\.yaml
  )$
```

Per-hook exclusions:

```yaml
- id: hook-name
  exclude: ^path/to/exclude/
```

## Best Practices

1. **Run hooks before pushing:** `pre-commit run --all-files`
2. **Update regularly:** `pre-commit autoupdate` monthly
3. **Don't skip security hooks:** Especially `detect-secrets` and `detect-private-key`
4. **Keep baselines updated:** Regenerate `.secrets.baseline` after legitimate changes
5. **Test in CI:** Run hooks in CI to catch issues on pull requests
6. **Document exceptions:** When skipping hooks, explain why in commit message

## Resources

- [Pre-commit documentation](https://pre-commit.com/)
- [FluxCD best practices](https://fluxcd.io/flux/guides/repository-structure/)
- [Kubeconform](https://github.com/yannh/kubeconform)
- [Kustomize](https://kustomize.io/)
- [detect-secrets](https://github.com/Yelp/detect-secrets)

## Support

For issues or questions:
1. Check this documentation
2. Review `.pre-commit-config.yaml` configuration
3. Test hooks manually with `pre-commit run`
4. Check hook output for specific error messages
