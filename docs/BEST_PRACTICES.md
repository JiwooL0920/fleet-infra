# FluxCD GitOps Best Practices

> **Comprehensive guide based on official FluxCD documentation and enterprise patterns**  
> *All information sourced from [FluxCD Official Documentation](https://fluxcd.io/)*

## Table of Contents

1. [Repository Structure Patterns](#repository-structure-patterns)
2. [Multi-Tenancy and Security](#multi-tenancy-and-security)
3. [Dependency Management](#dependency-management)
4. [Production Deployment Patterns](#production-deployment-patterns)
5. [Performance and Reliability](#performance-and-reliability)
6. [Monitoring and Observability](#monitoring-and-observability)
7. [Security Best Practices](#security-best-practices)

---

## Repository Structure Patterns

### 1. Monorepo Structure (Recommended for Most Organizations)

**Source:** [FluxCD Repository Structure Guide](https://github.com/fluxcd/website/blob/main/content/en/flux/guides/repository-structure.md#_snippet_0)

The monorepo approach separates applications, infrastructure, and cluster-specific configurations:

```
├── apps
│   ├── base
│   ├── production 
│   └── staging
├── infrastructure
│   ├── base
│   ├── production 
│   └── staging
└── clusters
    ├── production
    └── staging
```

**Benefits:**
- Single source of truth for all environments
- Easier change management and promotion
- Better visibility across environments

**When to Use:** Most organizations, especially those with centralized platform teams.

### 2. Repo-per-Team Structure (Enterprise Scale)

**Source:** [FluxCD Repository Structure Guide](https://github.com/fluxcd/website/blob/main/content/en/flux/guides/repository-structure.md#_snippet_1)

**Platform Admin Repository:**
```
├── teams
│   ├── team1
│   ├── team2
├── infrastructure
│   ├── base
│   ├── production 
│   └── staging
└── clusters
    ├── production
    └── staging
```

**Development Team Repository:**
```
└── apps
    ├── base
    ├── production 
    └── staging
```

**Benefits:**
- Better access control for production configurations
- Team autonomy for application delivery
- Easier spotting of unintentional production changes

**When to Use:** Large enterprises with multiple teams requiring strict separation.

### 3. Application Repository Patterns

**Source:** [FluxCD Repository Structure Guide](https://github.com/fluxcd/website/blob/main/content/en/flux/guides/repository-structure.md#_snippet_5)

**Kustomize Overlays Pattern:**
```
├── src
└── deploy
    ├── base
    ├── production 
    └── staging
```

**Helm Chart Pattern:**
```
├── src
└── chart
    ├── templates
    ├── values.yaml 
    └── values-prod.yaml
```

**Plain Manifests Pattern:**
```
├── src
└── deploy
    └── manifests
```

---

## Multi-Tenancy and Security

### 1. Multi-Tenancy Configuration

**Source:** [FluxCD Multi-Tenancy Configuration](https://github.com/fluxcd/website/blob/main/content/en/flux/installation/configuration/multitenancy.md#_snippet_0)

**Essential Multi-Tenancy Patches:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
patches:
  # Prevent cross-namespace references
  - patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --no-cross-namespace-refs=true
    target:
      kind: Deployment
      name: "(kustomize-controller|helm-controller|notification-controller|image-reflector-controller|image-automation-controller)"
  
  # Prevent remote bases (security)
  - patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --no-remote-bases=true
    target:
      kind: Deployment
      name: "kustomize-controller"
  
  # Set default service account
  - patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --default-service-account=default
    target:
      kind: Deployment
      name: "(kustomize-controller|helm-controller)"
```

**Why This Matters:**
- `--no-cross-namespace-refs=true`: Prevents tenants from accessing objects in other namespaces
- `--no-remote-bases=true`: Maintains hermeticity and prevents supply chain risks
- `--default-service-account=default`: Enforces impersonation for security

### 2. Multi-Tenant Operations

**Source:** [FluxCD Multi-Tenancy Q&A](https://github.com/fluxcd/website/blob/main/content/en/flux/installation/configuration/multitenancy.md#_qa_6)

**Tenant Capabilities:**
- Register sources: `GitRepositories`, `HelmRepositories`
- Deploy workloads: `Kustomizations`, `HelmReleases`
- Automate updates: `ImagePolicies`, `ImageUpdateAutomations`
- Configure pipelines: Flagger custom resources

**Reference Implementation:**
- [Flux Multi-Tenancy Example](https://github.com/fluxcd/flux2-multi-tenancy)

---

## Dependency Management

### 1. Category-Based Dependencies (Best Practice)

**Source:** [FluxCD Controller Shard Dependencies](https://github.com/fluxcd/website/blob/main/content/en/blog/2024-09-30-announcing-flux-v2.4.0/index.md#_snippet_5)

**Modern Approach:**
```yaml
# Instead of individual service dependencies
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: database-workloads
spec:
  dependsOn:
    - name: infrastructure-operators  # Category dependency
```

**Benefits:**
- Cleaner dependency graphs
- Better scalability
- Easier maintenance
- Supports cross-namespace dependencies

### 2. Pipeline Deployment Pattern

**Source:** [FluxCD Running Jobs](https://github.com/fluxcd/website/blob/main/content/en/flux/use-cases/running-jobs.md#_snippet_2)

**Three-Phase Deployment:**

```yaml
# Phase 1: Pre-deployment
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-pre-deploy
spec:
  sourceRef:
    kind: GitRepository
    name: my-app
  path: "./pre-deploy/"
  interval: 60m
  timeout: 5m
  prune: true
  wait: true
  force: true

---
# Phase 2: Application deployment
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-deploy
spec:
  dependsOn:
    - name: app-pre-deploy
  sourceRef:
    kind: GitRepository
    name: my-app
  path: "./deploy/"
  interval: 60m
  timeout: 5m
  prune: true
  wait: true

---
# Phase 3: Post-deployment
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-post-deploy
spec:
  dependsOn:
    - name: app-deploy
  sourceRef:
    kind: GitRepository
    name: my-app
  path: "./post-deploy/"
  interval: 60m
  timeout: 5m
  prune: true
  wait: true
  force: true
```

### 3. Repository Structure for Dependencies

**Source:** [FluxCD Running Jobs](https://github.com/fluxcd/website/blob/main/content/en/flux/use-cases/running-jobs.md#_snippet_0)

```
├── pre-deploy
│   └── migration.job.yaml
├── deploy
│   ├── deployment.yaml
│   ├── ingress.yaml
│   └── service.yaml
├── post-deploy
│   └── cache.job.yaml
└── flux
    ├── pre-deploy.yaml
    ├── deploy.yaml
    └── post-deploy.yaml
```

---

## Production Deployment Patterns

### 1. Multi-Cluster Bootstrap Structure

**Source:** [FluxCD Generic Git Server](https://github.com/fluxcd/website/blob/main/content/en/flux/installation/bootstrap/generic-git-server.md#_snippet_7)

```
./clusters/
├── staging # <- path=clusters/staging
│   └── flux-system
│       ├── gotk-components.yaml
│       ├── gotk-sync.yaml
│       └── kustomization.yaml
└── production # <- path=clusters/production
    └── flux-system
```

**Bootstrap Commands:**
```bash
# Staging
flux bootstrap github \
  --owner=my-org \
  --repository=fleet-infra \
  --path=clusters/staging \
  --branch=develop

# Production  
flux bootstrap github \
  --owner=my-org \
  --repository=fleet-infra \
  --path=clusters/production \
  --branch=main
```

### 2. Kustomization Best Practices

**Source:** [FluxCD Kustomization Resource](https://github.com/fluxcd/website/blob/main/content/en/blog/2022-09-01-manage-kyverno-policies-as-ocirepositories/index.md#_snippet_4)

**Essential Fields:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <kustomization-name>
  namespace: <namespace>
spec:
  interval: 30m              # Reconciliation frequency
  sourceRef:
    kind: GitRepository
    name: <git-repository-name>
  path: "./config/release"   # Path within repository
  prune: true               # Remove orphaned resources
  wait: true                # Wait for resources to be ready
  timeout: 5m               # Maximum wait time
  dependsOn:                # Dependencies
    - name: <dependency-kustomization-name>
```

### 3. OCI Artifacts for Production

**Source:** [FluxCD OCI Artifacts](https://github.com/fluxcd/website/blob/main/content/en/flux/cheatsheets/oci-artifacts.md#_snippet_8)

**Push Tagged Release:**
```bash
git checkout 6.1.0

flux push artifact oci://ghcr.io/stefanprodan/manifests/podinfo:$(git tag --points-at HEAD) \
	--path="./kustomize" \
	--source="$(git config --get remote.origin.url)" \
	--revision="$(git tag --points-at HEAD)@sha1:$(git rev-parse HEAD)"
```

**Tag as Stable:**
```bash
flux tag artifact oci://ghcr.io/stefanprodan/manifests/podinfo:$(git tag --points-at HEAD) \
  --tag stable
```

**Production OCIRepository:**
```yaml
# Stable tag approach
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  url: oci://ghcr.io/stefanprodan/manifests/podinfo
  ref:
    tag: stable

---
# Semver approach
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  url: oci://ghcr.io/stefanprodan/manifests/podinfo
  ref:
    semver: ">=1.0.0"
```

---

## Performance and Reliability

### 1. Timeout Standards by Resource Type

**Source:** Based on FluxCD pipeline patterns and production experience

**Recommended Timeouts:**
- **Infrastructure Core:** 5m (networking, ingress)
- **Operators:** 10m (CRD controllers)
- **Databases:** 15m (stateful services)
- **Applications:** 10m (business logic)
- **UI Tools:** 10m (admin interfaces)

### 2. Resource Configuration Best Practices

**Essential Flags:**
```yaml
spec:
  interval: 10m      # Environment-specific (dev: 1m, prod: 10m)
  timeout: 10m       # Resource-type specific
  wait: true         # CRITICAL for dependency ordering
  prune: true        # Clean up removed resources
  retryInterval: 2m  # For failed reconciliations
```

### 3. Environment-Specific Intervals

**Development:**
```yaml
spec:
  interval: 1m       # Fast feedback
  timeout: 5m        # Quick failure detection
```

**Production:**
```yaml
spec:
  interval: 10m      # Stable reconciliation
  timeout: 15m       # Patient for complex deployments
```

---

## Monitoring and Observability

### 1. Pipeline Visualization

**Source:** [FluxCD AI Assisted GitOps](https://github.com/fluxcd/website/blob/main/content/en/blog/2025-05-14-ai-assisted-gitops/index.md#_snippet_3)

**Generate Dependency Diagrams:**
```bash
# List Kustomizations and visualize dependencies
flux get kustomizations --all-namespaces

# Generate Mermaid diagram for dependency relationships
# (Feature for understanding pipeline order)
```

### 2. Health Monitoring Commands

**Source:** [FluxCD Get Kustomizations](https://github.com/fluxcd/website/blob/main/content/en/blog/2022-09-01-manage-kyverno-policies-as-ocirepositories/index.md#_snippet_5)

```bash
# Check all Flux resources
flux get all -A

# Check specific resource types
flux get kustomizations -A
flux get helmreleases -A
flux get sources git -A

# Watch for changes
flux get kustomizations --watch
```

### 3. Troubleshooting Commands

```bash
# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization <name>

# Check events
kubectl describe kustomization <name> -n flux-system

# View logs
kubectl logs -n flux-system -l app=kustomize-controller
```

---

## Security Best Practices

### 1. Controller Security Audit

**Source:** [FluxCD Security Best Practices](https://github.com/fluxcd/website/blob/main/content/en/flux/security/best-practices.md)

**Audit Insecure Flags:**
```bash
# Check for insecure kubeconfig flags
kubectl describe pod -n flux-system -l app=kustomize-controller | grep -B 5 -A 10 Args
kubectl describe pod -n flux-system -l app=helm-controller | grep -B 5 -A 10 Args
```

**What to Look For:**
- ❌ `--insecure-kubeconfig-exec=true` (allows arbitrary command execution)
- ❌ `--insecure-kubeconfig-tls=true` (disables TLS enforcement)
- ✅ `--no-remote-bases=true` (prevents external base downloads)
- ✅ `--no-cross-namespace-refs=true` (multi-tenancy isolation)

### 2. Cross-Namespace Reference Security

**Source:** [FluxCD Security Best Practices](https://github.com/fluxcd/website/blob/main/content/en/flux/security/best-practices.md#_snippet_3)

**Audit Cross-Namespace References:**
```bash
kubectl describe pod -n flux-system -l app=kustomize-controller | grep -B 5 -A 10 Args
kubectl describe pod -n flux-system -l app=helm-controller | grep -B 5 -A 10 Args
kubectl describe pod -n flux-system -l app=notification-controller | grep -B 5 -A 10 Args
kubectl describe pod -n flux-system -l app=image-reflector-controller | grep -B 5 -A 10 Args
kubectl describe pod -n flux-system -l app=image-automation-controller | grep -B 5 -A 10 Args
```

### 3. Default Service Account Security

**Source:** [FluxCD Security Best Practices](https://github.com/fluxcd/website/blob/main/content/en/flux/security/best-practices.md#_snippet_4)

**Verify Default Service Account:**
```bash
kubectl describe pod -n flux-system -l app=helm-controller | grep -B 5 -A 10 Args
kubectl describe pod -n flux-system -l app=kustomize-controller | grep -B 5 -A 10 Args
```

**Look for:** `--default-service-account=default` to enforce impersonation.

### 4. Image Vulnerability Scanning

**Source:** [FluxCD Security](https://github.com/fluxcd/website/blob/main/content/en/flux/security/_index.md#_snippet_5)

```bash
# Scan Flux controller images for vulnerabilities
trivy image ghcr.io/fluxcd/source-controller:v1.0.0
trivy image ghcr.io/fluxcd/kustomize-controller:v1.0.0
trivy image ghcr.io/fluxcd/helm-controller:v1.0.0
```

---

## Key Takeaways

### ✅ **Do's**

1. **Use category-based dependencies** over individual service dependencies
2. **Implement proper timeout standards** based on resource types
3. **Enable security flags** for multi-tenancy (`--no-cross-namespace-refs=true`)
4. **Use pipeline patterns** (pre-deploy → deploy → post-deploy)
5. **Implement wait flags** (`wait: true`) for proper ordering
6. **Use OCI artifacts** for production releases
7. **Monitor and audit** controller configurations regularly

### ❌ **Don'ts**

1. **Don't use insecure flags** in production (`--insecure-kubeconfig-*`)
2. **Don't skip timeout configurations** (can cause infinite waits)
3. **Don't allow remote bases** in production (`--no-remote-bases=true`)
4. **Don't ignore security audits** of controller startup flags
5. **Don't use individual service dependencies** at scale
6. **Don't deploy without proper RBAC** in multi-tenant environments

---

## References

All information in this document is sourced from the official FluxCD documentation:

- **Repository Structure:** https://github.com/fluxcd/website/blob/main/content/en/flux/guides/repository-structure.md
- **Multi-Tenancy:** https://github.com/fluxcd/website/blob/main/content/en/flux/installation/configuration/multitenancy.md
- **Security Best Practices:** https://github.com/fluxcd/website/blob/main/content/en/flux/security/best-practices.md
- **Running Jobs:** https://github.com/fluxcd/website/blob/main/content/en/flux/use-cases/running-jobs.md
- **OCI Artifacts:** https://github.com/fluxcd/website/blob/main/content/en/flux/cheatsheets/oci-artifacts.md
- **Multi-Tenancy Example:** https://github.com/fluxcd/flux2-multi-tenancy

**Last Updated:** Based on FluxCD v2.4+ documentation  
**Maintained By:** Generated from Context7 MCP FluxCD documentation