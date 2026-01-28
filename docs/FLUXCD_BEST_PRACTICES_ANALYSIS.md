# FluxCD Best Practices Analysis

> **Comprehensive analysis of fleet-infra repository against FluxCD official best practices**  
> *Analysis Date: January 28, 2026*

## Executive Summary

This document analyzes the current `fleet-infra` repository structure against FluxCD official best practices, patterns from the [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) reference implementation, and community patterns.

### Overall Assessment: **Good Foundation with Room for Improvement**

| Category | Current State | Best Practice Alignment |
|----------|---------------|------------------------|
| Repository Structure | Custom hybrid | Partial - needs refactoring |
| Dependency Management | Fine-grained | Good - well implemented |
| Environment Separation | Branch-based | Good |
| API Versioning | Mixed versions | Needs standardization |
| CI/CD Testing | Missing | Critical gap |
| Secrets Management | External Secrets | Good |
| Documentation | Extensive | Good |

---

## 1. Repository Structure Analysis

### Current Structure

```
fleet-infra/
├── apps/
│   └── base/           # Service Kubernetes manifests
│       ├── traefik/
│       ├── redis/
│       ├── n8n/
│       └── ...
├── base/
│   └── services/       # Flux Kustomization definitions
│       ├── kustomization.yaml
│       ├── traefik.yaml
│       ├── redis.yaml
│       └── ...
├── clusters/
│   └── stages/
│       ├── dev/clusters/services-amer/
│       └── prod/clusters/services-amer/
├── docs/
└── scripts/
```

### FluxCD Recommended Structure

```
fleet-infra/
├── apps/
│   ├── base/           # Base app definitions
│   ├── staging/        # Staging overlays
│   └── production/     # Production overlays
├── infrastructure/
│   ├── controllers/    # Operators and controllers
│   └── configs/        # CRDs and configurations
└── clusters/
    ├── staging/        # Cluster-specific Flux config
    └── production/
```

### Findings

| Issue | Severity | Description |
|-------|----------|-------------|
| **Mixed concerns in `apps/base/`** | Medium | Infrastructure controllers (traefik, cnpg-operator) mixed with applications (n8n, temporal) |
| **Nested cluster paths** | Low | `clusters/stages/dev/clusters/services-amer` is overly nested |
| **No `infrastructure/` separation** | Medium | No clear separation between infrastructure (operators) and applications |
| **No environment overlays** | Medium | Apps don't have staging/production overlays under `apps/` |

### Recommendations

#### 1.1 Separate Infrastructure from Applications

**Why:** The official FluxCD pattern separates infrastructure (controllers, operators) from applications. This enables:
- Different reconciliation intervals
- Independent deployment pipelines
- Clearer dependency management

**Proposed Structure:**

```
fleet-infra/
├── infrastructure/
│   ├── controllers/                    # Operators and CRD controllers
│   │   ├── kustomization.yaml
│   │   ├── traefik.yaml
│   │   ├── cnpg-operator.yaml
│   │   ├── external-secrets-operator.yaml
│   │   ├── crossplane.yaml
│   │   └── metrics-server.yaml
│   └── configs/                        # CRDs, ClusterSecretStore, etc.
│       ├── kustomization.yaml
│       ├── external-secrets-config.yaml
│       ├── traefik-config.yaml
│       └── postgresql-cluster.yaml
├── apps/
│   ├── base/                           # Business applications
│   │   ├── n8n/
│   │   ├── temporal/
│   │   └── ...
│   ├── staging/                        # Staging overlays
│   │   └── kustomization.yaml
│   └── production/                     # Production overlays
│       └── kustomization.yaml
└── clusters/
    ├── staging/                        # Simplified paths
    │   ├── infrastructure.yaml
    │   ├── apps.yaml
    │   └── flux-system/
    └── production/
```

#### 1.2 Simplify Cluster Paths

**Current:** `clusters/stages/dev/clusters/services-amer/`
**Recommended:** `clusters/staging/` or `clusters/dev/`

**Why:** Simpler paths are easier to maintain and align with official examples.

---

## 2. Dependency Management

### Current Implementation: **GOOD**

Your fine-grained dependency approach is well-implemented:

```yaml
# Example from base/services/n8n.yaml
spec:
  dependsOn:
    - name: external-secrets-config
    - name: postgresql-cluster
```

### Best Practice Comparison

| Pattern | Your Repo | Official Recommendation |
|---------|-----------|------------------------|
| `dependsOn` usage | ✅ Yes | ✅ Recommended |
| `wait: true` | ✅ Yes | ✅ Critical for ordering |
| `healthChecks` | ✅ Some | ⚠️ Should be more consistent |
| Category-based deps | ❌ No | ✅ Recommended for scale |

### Recommendations

#### 2.1 Add Health Checks Consistently

**Current:** Only some Kustomizations have healthChecks

```yaml
# base/services/traefik.yaml - HAS healthChecks
healthChecks:
  - apiVersion: apps/v1
    kind: Deployment
    name: traefik
    namespace: traefik
```

```yaml
# base/services/n8n.yaml - MISSING healthChecks
# No healthChecks defined
```

**Recommendation:** Add healthChecks to ALL service Kustomizations:

```yaml
# base/services/n8n.yaml
spec:
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: n8n
      namespace: n8n
```

#### 2.2 Consider Category-Based Dependencies (Future Scale)

For larger deployments, group services into categories:

```yaml
# Instead of 20+ individual Kustomizations
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-controllers    # Category: all operators
spec:
  path: ./infrastructure/controllers
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization  
metadata:
  name: infra-configs        # Category: all configs
spec:
  dependsOn:
    - name: infra-controllers
  path: ./infrastructure/configs
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps                 # Category: all apps
spec:
  dependsOn:
    - name: infra-configs
  path: ./apps/staging
```

---

## 3. API Version Consistency

### Current State: **NEEDS ATTENTION**

Mixed API versions found across the repository:

| Resource Type | Versions Found | Recommended |
|---------------|----------------|-------------|
| HelmRelease | `v2`, `v2beta2` | `v2` |
| HelmRepository | `v1`, `v1beta2` | `v1` |
| Kustomization | `v1` | `v1` ✅ |
| GitRepository | `v1` | `v1` ✅ |

### Files with Outdated API Versions

```
apps/base/promtail/helmrelease.yaml      → helm.toolkit.fluxcd.io/v2beta2
apps/base/loki/helmrelease.yaml          → helm.toolkit.fluxcd.io/v2beta2, source.toolkit.fluxcd.io/v1beta2
apps/base/redis/helmrelease.yaml         → helm.toolkit.fluxcd.io/v2beta2, source.toolkit.fluxcd.io/v1beta2
apps/base/weave-gitops/helmrelease.yaml  → source.toolkit.fluxcd.io/v1beta2
```

### Recommendation

Upgrade all resources to stable API versions:

```yaml
# Before
apiVersion: helm.toolkit.fluxcd.io/v2beta2
apiVersion: source.toolkit.fluxcd.io/v1beta2

# After
apiVersion: helm.toolkit.fluxcd.io/v2
apiVersion: source.toolkit.fluxcd.io/v1
```

---

## 4. CI/CD Testing Gap

### Current State: **CRITICAL GAP**

No `.github/workflows/` directory exists. The official FluxCD example includes:

1. **Manifest Validation** (`test.yaml`) - Validates YAML and Kustomize overlays
2. **E2E Testing** (`e2e.yaml`) - Deploys to Kind cluster in CI

### Recommendation: Add CI Workflows

#### 4.1 Manifest Validation Workflow

Create `.github/workflows/test.yaml`:

```yaml
name: test

on:
  workflow_dispatch:
  pull_request:
  push:
    branches: ['*']
    tags-ignore: ['*']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5
      
      - name: Setup yq
        uses: fluxcd/pkg/actions/yq@main
      
      - name: Setup kubeconform
        uses: fluxcd/pkg/actions/kubeconform@main
      
      - name: Setup kustomize
        uses: fluxcd/pkg/actions/kustomize@main
      
      - name: Validate manifests
        run: ./scripts/validate.sh
```

#### 4.2 Validation Script

Create `scripts/validate.sh`:

```bash
#!/usr/bin/env bash
set -o errexit
set -o pipefail

# Download Flux CRD schemas
echo "INFO - Downloading Flux OpenAPI schemas"
mkdir -p /tmp/flux-crd-schemas/master-standalone-strict
curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | \
  tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict

# Validate YAML syntax
find . -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file; do
  echo "INFO - Validating $file"
  yq e 'true' "$file" > /dev/null
done

# Validate Kustomize overlays
kubeconform_config=("-strict" "-ignore-missing-schemas" \
  "-schema-location" "default" \
  "-schema-location" "/tmp/flux-crd-schemas" "-verbose")

find . -type f -name 'kustomization.yaml' -print0 | while IFS= read -r -d $'\0' file; do
  dir="${file/%kustomization.yaml/}"
  echo "INFO - Validating kustomization ${dir}"
  kustomize build "$dir" --load-restrictor=LoadRestrictionsNone | \
    kubeconform -skip=Secret "${kubeconform_config[@]}"
done
```

---

## 5. Environment Configuration

### Current State: **GOOD**

Using ConfigMap with variable substitution:

```yaml
# base/services/kustomization.yaml
configMapGenerator:
  - name: cluster-vars
    envs:
      - environment.env
```

```yaml
# Service Kustomizations
postBuild:
  substituteFrom:
    - kind: ConfigMap
      name: cluster-vars
```

### Best Practice Alignment: ✅

This aligns with FluxCD's recommended approach for environment-specific configuration.

### Minor Improvement

Consider using Kustomize patches for environment-specific HelmRelease values instead of only ConfigMap substitution:

```yaml
# clusters/staging/apps.yaml
spec:
  patches:
    - patch: |-
        - op: replace
          path: /spec/values/replicas
          value: 1
      target:
        kind: HelmRelease
        labelSelector: "environment=staging"
```

---

## 6. Secrets Management

### Current State: **GOOD**

Using External Secrets Operator with LocalStack:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-admin-credentials
spec:
  secretStoreRef:
    name: localstack-secretstore
    kind: ClusterSecretStore
```

### Best Practice Alignment: ✅

- No hardcoded secrets in Git
- External Secrets Operator for secret synchronization
- ClusterSecretStore for centralized management

### Recommendation

Consider adding SOPS support for encrypted secrets as a backup option when External Secrets is unavailable.

---

## 7. Missing Features from Official Example

### 7.1 ArtifactGenerator (Flux 2.4+)

The official example uses `ArtifactGenerator` to split the monorepo:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: ArtifactGenerator
metadata:
  name: flux-system
spec:
  interval: 1h
  artifacts:
    - name: apps
      fromPaths:
        - ./apps/base
        - ./apps/${CLUSTER_ENV}
    - name: infrastructure
      fromPaths:
        - ./infrastructure
```

**Benefit:** Changes to files outside relevant paths don't trigger unnecessary reconciliations.

### 7.2 OCI Repository Support

Consider using OCI repositories for Helm charts instead of Git-based sources:

```yaml
# Modern approach
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: cert-manager
spec:
  url: oci://quay.io/jetstack/charts/cert-manager
  ref:
    semver: "1.x"
```

### 7.3 Flux Operator (Enterprise Pattern)

For fleet management, consider the [Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator):

- Automated Flux controller upgrades
- FluxInstance CRD for declarative configuration
- Better multi-cluster management

---

## 8. Comparison with Official Example

| Feature | fleet-infra | flux2-kustomize-helm-example |
|---------|-------------|------------------------------|
| Apps/Infra separation | ❌ Mixed | ✅ Separated |
| Environment overlays | ⚠️ Partial | ✅ Full |
| CI validation | ❌ Missing | ✅ test.yaml |
| E2E testing | ❌ Missing | ✅ e2e.yaml |
| ArtifactGenerator | ❌ No | ✅ Yes |
| Health checks | ⚠️ Partial | ✅ Consistent |
| API versions | ⚠️ Mixed | ✅ Consistent |
| Documentation | ✅ Extensive | ✅ README |
| Secrets management | ✅ External Secrets | N/A |
| Fine-grained deps | ✅ Yes | ✅ Category-based |

---

## 9. Prioritized Action Items

### High Priority

1. **Add CI/CD Workflows** - Critical for preventing broken deployments
   - Add `.github/workflows/test.yaml` for manifest validation
   - Add `scripts/validate.sh` for validation logic

2. **Standardize API Versions** - Prevent deprecation issues
   - Update all `v2beta2` → `v2`
   - Update all `v1beta2` → `v1`

3. **Add Health Checks to All Kustomizations** - Improve reliability
   - Review each service in `base/services/`
   - Add appropriate healthChecks

### Medium Priority

4. **Separate Infrastructure from Applications**
   - Create `infrastructure/controllers/` for operators
   - Create `infrastructure/configs/` for CRDs and configs
   - Move apps to clean `apps/` structure

5. **Simplify Cluster Paths**
   - Refactor `clusters/stages/dev/clusters/services-amer/` → `clusters/staging/`

6. **Add Environment Overlays**
   - Create `apps/staging/` and `apps/production/` for patches

### Low Priority

7. **Consider ArtifactGenerator** - For optimized reconciliation

8. **Evaluate Flux Operator** - For enterprise fleet management

9. **Add OCI Repository Support** - For production Helm charts

---

## 10. Migration Strategy

### Phase 1: Quick Wins (No Structural Changes)

1. Add CI workflows
2. Standardize API versions
3. Add missing healthChecks

### Phase 2: Structure Improvements

1. Create `infrastructure/` directory
2. Move operators and configs
3. Update cluster Kustomizations to reference new paths

### Phase 3: Advanced Patterns

1. Implement ArtifactGenerator
2. Add environment overlays
3. Consider Flux Operator for fleet management

---

## References

- [FluxCD Official Documentation](https://fluxcd.io/flux/)
- [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)
- [FluxCD Repository Structure Guide](https://fluxcd.io/flux/guides/repository-structure/)
- [FluxCD Security Best Practices](https://fluxcd.io/flux/security/best-practices/)
- [Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator)

---

*This analysis was generated by comparing the fleet-infra repository against FluxCD official best practices and the reference implementation.*
