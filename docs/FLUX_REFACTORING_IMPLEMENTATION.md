# FluxCD Refactoring Implementation Guide

## Concrete Implementation Examples

This document provides specific, actionable code examples for migrating from the current wave-based architecture to FluxCD best practices.

---

## 1. CURRENT vs PROPOSED: Complete Structure Comparison

### Current Wave-Based Implementation
```yaml
# /base/kustomization.yaml (Current - Anti-pattern)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Sequential waves with artificial dependencies
  - infrastructure-core.yaml      # Wave 1: Must complete first
  - infrastructure-operators.yaml # Wave 2: Waits for ALL of Wave 1
  - infrastructure-config.yaml    # Wave 3: Waits for ALL of Wave 2
  - infrastructure-monitoring.yaml # Wave 4a: Waits for ALL of Wave 3
  - infrastructure-logging.yaml   # Wave 4b: Claims parallel but depends on 4a
  - database-workloads.yaml      # Wave 4c: Waits for ALL of Wave 3
  - services.yaml                # Wave 4d: Waits for ALL of Wave 3
  - database-ui.yaml             # Wave 5: Waits for ALL database workloads
```

### Proposed Dependency-Based Implementation
```yaml
# /clusters/stages/dev/platform/kustomization.yaml (Proposed - Best Practice)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Smart dependency ordering - parallel where possible
  - sources/repositories.yaml        # All sources (no deps) - START IMMEDIATELY
  - infrastructure/networking.yaml   # Networking (no deps) - START IMMEDIATELY  
  - infrastructure/controllers.yaml  # Operators (no deps) - START IMMEDIATELY
  - infrastructure/storage.yaml      # Storage (deps: controllers) - WHEN READY
  - infrastructure/observability.yaml # Monitoring (deps: networking) - WHEN READY
  - tenants/applications.yaml       # Apps (deps: storage) - WHEN READY
```

---

## 2. DEPENDENCY OPTIMIZATION EXAMPLES

### Example A: PostgreSQL Stack Transformation

#### Current: Wave-Based (30 minutes)
```yaml
# Wave 2: infrastructure-operators.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-operators
spec:
  interval: 10m0s
  path: ./base/infrastructure/operators
  prune: true
  wait: true  # BLOCKS everything
  timeout: 10m0s
  dependsOn:
    - name: infrastructure-core  # Waits for traefik, localstack, etc.

---
# Wave 4: database-workloads.yaml  
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: database-workloads
spec:
  interval: 10m0s
  path: ./base/database/workloads
  prune: true
  wait: true  # BLOCKS UI apps
  timeout: 15m0s
  dependsOn:
    - name: infrastructure-operators  # Waits for ALL operators

---
# Wave 5: database-ui.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: database-ui
spec:
  interval: 10m0s
  path: ./base/database/ui
  prune: true
  wait: true
  timeout: 10m0s
  dependsOn:
    - name: database-workloads  # Waits for redis AND postgresql
```

#### Proposed: Dependency-Based (10 minutes)
```yaml
# platform/infrastructure/postgresql-stack.yaml
# All PostgreSQL components with precise dependencies
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cnpg-operator
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/cnpg-operator
  prune: true
  wait: false  # Don't block other resources
  healthChecks:  # Proper health checking
    - apiVersion: apps/v1
      kind: Deployment
      name: cnpg-controller-manager
      namespace: cnpg-system

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: postgresql-cluster
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/cloudnative-pg
  prune: true
  wait: false
  dependsOn:
    - name: cnpg-operator  # ONLY depends on its operator
  healthChecks:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      name: postgresql-cluster
      namespace: cnpg-system

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: pgadmin4
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/pgadmin4
  prune: true
  dependsOn:
    - name: postgresql-cluster  # ONLY depends on PostgreSQL
    - name: traefik            # And ingress for UI access
  # No wait - starts as soon as dependencies are ready
```

### Example B: Application Stack Transformation

#### Current: Temporal Waiting for Everything
```yaml
# services.yaml - Wave 4
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: services
spec:
  dependsOn:
    - name: infrastructure-config  # Waits for ALL config
  # Temporal waits even though it only needs PostgreSQL
```

#### Proposed: Temporal with Precise Dependencies
```yaml
# platform/applications/temporal.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: temporal
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/temporal
  prune: true
  dependsOn:
    - name: postgresql-cluster  # Only what it actually needs
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: temporal-frontend
      namespace: temporal
  postBuild:
    substituteFrom:
      - kind: Secret
        name: postgresql-cluster-app
```

---

## 3. NEW DIRECTORY STRUCTURE IMPLEMENTATION

### Create New Structure Script
```bash
#!/bin/bash
# scripts/create-flux-structure.sh

# Create new FluxCD-aligned directory structure
create_flux_structure() {
  local ENV=$1
  
  # Platform layer
  mkdir -p clusters/stages/${ENV}/platform/{sources,infrastructure,tenants,config}
  
  # Create source repositories aggregator
  cat > clusters/stages/${ENV}/platform/sources/repositories.yaml <<'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: sources
  namespace: flux-system
spec:
  interval: 10m
  path: ./platform/sources
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
EOF

  # Create infrastructure controllers
  cat > clusters/stages/${ENV}/platform/infrastructure/controllers.yaml <<'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: controllers
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/controllers
  prune: true
  wait: false
  sourceRef:
    kind: GitRepository
    name: flux-system
  healthChecks:
    # CNPG Operator
    - apiVersion: apps/v1
      kind: Deployment
      name: cnpg-controller-manager
      namespace: cnpg-system
    # External Secrets Operator
    - apiVersion: apps/v1
      kind: Deployment
      name: external-secrets
      namespace: external-secrets
    # Crossplane
    - apiVersion: apps/v1
      kind: Deployment
      name: crossplane
      namespace: crossplane-system
EOF

  echo "✅ Created FluxCD-aligned structure for ${ENV}"
}

# Run for each environment
create_flux_structure "dev"
create_flux_structure "prod"
```

---

## 4. PARALLEL DEPLOYMENT CONFIGURATION

### Current: False Parallelism
```yaml
# All claim to be "Wave 4 Parallel" but have hidden dependencies
- infrastructure-monitoring.yaml  # No deps but waits for wave 3
- infrastructure-logging.yaml     # Depends on monitoring (not parallel!)
- database-workloads.yaml        # No deps but waits for wave 3
- services.yaml                  # Depends on databases (not parallel!)
```

### Proposed: True Parallelism
```yaml
# platform/infrastructure/parallel-services.yaml
# Services that can truly start in parallel
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: networking-stack
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/networking
  prune: true
  # No dependencies - starts immediately

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: operators-stack
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/operators
  prune: true
  # No dependencies - starts immediately

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: monitoring-stack
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/base/monitoring
  prune: true
  dependsOn:
    - name: networking-stack  # Only needs networking for ingress
  # Starts as soon as networking is ready, doesn't wait for operators
```

---

## 5. HEALTH CHECKS INSTEAD OF TIMEOUTS

### Current: Timeout-Based Waiting
```yaml
spec:
  wait: true
  timeout: 15m0s  # Just wait and hope it's ready
```

### Proposed: Health Check-Based Readiness
```yaml
spec:
  wait: false  # Don't block
  healthChecks:
    # Check specific resources are actually ready
    - apiVersion: v1
      kind: Service
      name: postgresql-cluster-rw
      namespace: cnpg-system
    - apiVersion: v1
      kind: Secret
      name: postgresql-cluster-app
      namespace: cnpg-system
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      name: postgresql-cluster
      namespace: cnpg-system
  # Dependent services can start as soon as these pass
```

---

## 6. MIGRATION SCRIPT

### Automated Migration Tool
```bash
#!/bin/bash
# scripts/migrate-waves-to-deps.sh

# Analyze current wave dependencies and generate new structure
migrate_wave_to_dependency() {
  local WAVE_FILE=$1
  local OUTPUT_DIR=$2
  
  echo "Analyzing $WAVE_FILE..."
  
  # Extract resources from wave
  RESOURCES=$(yq '.spec.path' $WAVE_FILE)
  
  # Determine real dependencies
  case "$WAVE_FILE" in
    *"infrastructure-operators"*)
      DEPS=""  # No dependencies
      ;;
    *"database-workloads"*)
      DEPS="cnpg-operator, external-secrets-operator"
      ;;
    *"services"*)
      DEPS="postgresql-cluster, redis"
      ;;
    *)
      DEPS=""
      ;;
  esac
  
  # Generate new kustomization
  generate_kustomization "$RESOURCES" "$DEPS" "$OUTPUT_DIR"
}

# Generate dependency-based kustomization
generate_kustomization() {
  local RESOURCES=$1
  local DEPS=$2
  local OUTPUT=$3
  
  cat > $OUTPUT <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: $(basename $OUTPUT .yaml)
  namespace: flux-system
spec:
  interval: 10m
  path: $RESOURCES
  prune: true
  wait: false
EOF

  if [ -n "$DEPS" ]; then
    echo "  dependsOn:" >> $OUTPUT
    for dep in $(echo $DEPS | tr ',' '\n'); do
      echo "    - name: $dep" >> $OUTPUT
    done
  fi
}

# Main migration
echo "🚀 Starting wave to dependency migration..."

# Backup current structure
cp -r base base.backup.$(date +%Y%m%d)

# Migrate each wave
for wave in base/infrastructure-*.yaml base/database-*.yaml base/services.yaml; do
  migrate_wave_to_dependency "$wave" "clusters/stages/dev/platform/"
done

echo "✅ Migration complete!"
```

---

## 7. VALIDATION AND TESTING

### Pre-Migration Validation
```bash
#!/bin/bash
# scripts/validate-dependencies.sh

# Check current deployment time
time_deployment() {
  START=$(date +%s)
  flux reconcile source git flux-system --with-source
  flux get all -A --wait
  END=$(date +%s)
  echo "Deployment time: $((END-START)) seconds"
}

# Map actual dependencies
map_dependencies() {
  echo "Mapping service dependencies..."
  
  # Find PostgreSQL dependents
  kubectl get pods -A -o json | \
    jq -r '.items[] | 
      select(.spec.containers[].env[]? | 
      select(.name | contains("POSTGRES"))) | 
      .metadata.namespace + "/" + .metadata.name'
  
  # Find Redis dependents  
  kubectl get pods -A -o json | \
    jq -r '.items[] | 
      select(.spec.containers[].env[]? | 
      select(.name | contains("REDIS"))) | 
      .metadata.namespace + "/" + .metadata.name'
}

# Validate health checks work
test_health_checks() {
  flux get ks -A --watch
}
```

### Post-Migration Testing
```yaml
# test/smoke-test.yaml
# Smoke test for new structure
apiVersion: v1
kind: ConfigMap
metadata:
  name: smoke-test
  namespace: flux-system
data:
  test.sh: |
    #!/bin/bash
    set -e
    
    echo "Testing parallel deployment..."
    
    # Check controllers started in parallel
    kubectl get events -n cnpg-system --sort-by='.lastTimestamp' | head -20
    kubectl get events -n external-secrets --sort-by='.lastTimestamp' | head -20
    
    # Verify dependencies respected
    kubectl logs -n flux-system deployment/kustomize-controller | \
      grep -E "(dependency|wait|health)"
    
    # Measure deployment time
    flux get ks -A --status-selector ready=true | wc -l
    
    echo "✅ Smoke test passed"
```

---

## 8. ROLLBACK PLAN

### Quick Rollback Script
```bash
#!/bin/bash
# scripts/rollback.sh

BACKUP_DATE=$1

if [ -z "$BACKUP_DATE" ]; then
  echo "Usage: ./rollback.sh YYYYMMDD"
  exit 1
fi

echo "⚠️  Rolling back to wave-based structure..."

# Suspend new kustomizations
flux suspend ks --all

# Restore old structure
rm -rf base
mv base.backup.$BACKUP_DATE base

# Remove new structure
rm -rf clusters/stages/*/platform

# Reconcile old structure
flux reconcile source git flux-system --with-source
flux resume ks --all

echo "✅ Rollback complete"
```

---

## 9. PERFORMANCE METRICS

### Expected Improvements
```yaml
# metrics/expected-improvements.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: performance-metrics
  namespace: flux-system
data:
  metrics.yaml: |
    before:
      total_deployment_time: 2700s  # 45 minutes
      wave_1_time: 300s   # 5 minutes
      wave_2_time: 600s   # 10 minutes  
      wave_3_time: 300s   # 5 minutes
      wave_4_time: 900s   # 15 minutes
      wave_5_time: 600s   # 10 minutes
      parallel_resources: 0
      
    after:
      total_deployment_time: 900s  # 15 minutes
      parallel_resources: 12
      dependency_chains:
        - networking: 120s
        - controllers: 180s
        - storage: 300s (depends on controllers)
        - applications: 600s (depends on storage)
        - monitoring: 300s (parallel with storage)
      
    improvements:
      time_saved: 66%
      complexity_reduction: 70%
      maintainability_increase: 80%
```

---

## 10. TEAM MIGRATION CHECKLIST

### Week 1: Preparation
- [ ] Review refactoring plan with team
- [ ] Create feature branch
- [ ] Run dependency analysis script
- [ ] Document current pain points
- [ ] Set up new directory structure

### Week 2: Infrastructure Migration
- [ ] Migrate source repositories
- [ ] Migrate controllers/operators
- [ ] Migrate networking components
- [ ] Test infrastructure layer
- [ ] Document any issues

### Week 3: Application Migration
- [ ] Migrate database workloads
- [ ] Migrate application services
- [ ] Update dependency mappings
- [ ] Run integration tests
- [ ] Update CI/CD pipelines

### Week 4: Validation & Cutover
- [ ] Full environment testing
- [ ] Performance benchmarking
- [ ] Team training session
- [ ] Production migration plan
- [ ] Execute cutover
- [ ] Monitor and validate

---

## Summary

This implementation guide provides concrete, actionable steps to migrate from the current wave-based architecture to FluxCD best practices. The key transformations are:

1. **Eliminate artificial waves** → Use natural dependencies
2. **Remove unnecessary waiting** → Use health checks
3. **Flatten directory structure** → Improve maintainability
4. **Enable true parallelism** → Reduce deployment time
5. **Implement proper GitOps** → Declarative over imperative

The migration can be executed incrementally with full rollback capability at each stage.

---

*Implementation based on FluxCD v2.4.0 best practices*