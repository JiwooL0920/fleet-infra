# Environment-Specific Configuration Management Implementation Plan

## Executive Summary

This document provides a comprehensive implementation plan for GitHub Issue #5: implementing environment-specific configuration management for our GitOps infrastructure. The plan focuses on creating environment.env overlay files in cluster-specific paths to separate configuration from application definitions while maintaining our successful fine-grained GitOps architecture.

**Key Objectives:**
- Extract hardcoded values from 21 services into centralized configuration
- Implement environment-specific overlays in dev/prod cluster paths
- Maintain zero-downtime migration with comprehensive rollback procedures
- Preserve our 8-12 minute fine-grained deployment performance
- Enable rapid environment provisioning and configuration management

---

## Current State Analysis

### Existing Architecture Strengths
- **Fine-grained GitOps**: 21 services with optimized wave-based dependencies
- **Fast deployments**: 8-12 minute total deployment time with parallel execution
- **Robust dependency management**: Services deploy in proper order with health checks
- **Existing configuration foundation**: Base environment.env with basic variables

### Configuration Debt Identified
From analysis of current HelmRelease files, the following hardcoded values need extraction:

**Redis (apps/base/redis/helmrelease.yaml):**
- Chart version: `20.3.0`
- Resource limits: Memory 256Mi/512Mi, CPU 100m/500m
- Replica count: `2`, Master count: `1`
- Storage size: `8Gi`
- Sentinel settings: downAfterMilliseconds `30000`, failoverTimeout `180000`

**Loki (apps/base/loki/helmrelease.yaml):**
- Chart version: `6.16.0`
- Resource limits: Memory 512Mi/1Gi, CPU 250m/500m
- Storage size: `10Gi`
- Cache timeouts: `500ms`, expiration `1h`
- Retention period: `720h` (30 days)
- Redis connection pool sizes: `10`, `5`

**Additional Services**: PostgreSQL, Traefik, Prometheus Stack, N8N, Temporal, and others contain similar hardcoded configurations.

---

## Implementation Architecture

### Environment-Specific Configuration Structure

Following the GitHub issue requirements for environment.env files in cluster paths:

```
fleet-infra/
├── base/services/environment.env                                    # Base defaults
├── clusters/stages/dev/clusters/services-amer/environment.env      # Dev overrides
└── clusters/stages/prod/clusters/services-amer/environment.env     # Prod overrides (new)
```

### Variable Naming Convention

Using the format specified in the GitHub issue: `APP_NAME_SETTING_NAME=value`

**Examples:**
```bash
# Chart versions (consistent across environments)
REDIS_CHART_VERSION=20.3.0
LOKI_CHART_VERSION=6.16.0
POSTGRESQL_CHART_VERSION=15.5.0

# Resource configurations (environment-specific)
REDIS_MASTER_MEMORY_LIMIT=512Mi
REDIS_REPLICA_COUNT=2
LOKI_MEMORY_LIMIT=1Gi
LOKI_STORAGE_SIZE=10Gi

# Performance tuning (environment-specific)
LOKI_RETENTION_PERIOD=720h
REDIS_SENTINEL_TIMEOUT=30000
```

### Flux CD Integration Pattern

**ConfigMap Generation:**
```yaml
# base/services/kustomization.yaml
configMapGenerator:
  - name: cluster-vars
    envs:
      - environment.env
    options:
      disableNameSuffixHash: true
    namespace: flux-system
```

**Variable Substitution:**
```yaml
# clusters/stages/{env}/clusters/services-amer/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../../../../base/services

postBuild:
  substituteFrom:
    - kind: ConfigMap
      name: cluster-vars
      optional: false

configMapGenerator:
  - name: cluster-vars
    behavior: merge
    envs:
      - environment.env
    options:
      disableNameSuffixHash: true
    namespace: flux-system
```

---

## Implementation Phases

### Phase 1: Foundation Setup (Week 1)

**Objectives:**
- Create missing prod environment structure
- Extend base configuration with all application variables
- Set up environment-specific overlay files
- Update kustomization infrastructure

**Deliverables:**
- [ ] Complete prod environment directory structure
- [ ] Comprehensive base/services/environment.env with all application variables
- [ ] Dev/prod overlay environment.env files with optimized values
- [ ] Updated kustomization files for ConfigMap generation and substitution

### Phase 2: Pilot Implementation (Week 2)

**Objectives:**
- Validate approach with Redis and Loki migrations
- Test environment-specific value substitution
- Establish validation and rollback procedures

**Target Applications:**
- **Redis**: Medium complexity, clear resource patterns
- **Loki**: High complexity with multiple cache configurations

**Success Criteria:**
- Zero service downtime during migration
- Identical application behavior post-migration
- Successful environment-specific resource allocation
- Validated rollback procedures

### Phase 3: Critical Infrastructure (Week 3)

**Objectives:**
- Migrate mission-critical infrastructure services
- Maintain high availability during migration
- Establish production environment confidence

**Target Applications:**
- PostgreSQL cluster (highest risk, most critical)
- Traefik ingress controller
- External Secrets Operator
- CNPG Operator

### Phase 4: Application Services (Week 4)

**Objectives:**
- Complete migration of application workloads
- Validate cross-service configurations
- Optimize environment-specific performance

**Target Applications:**
- N8N workflow automation
- Temporal orchestration
- Monitoring stack (Prometheus, Grafana)
- Database UIs (pgAdmin4, RedisInsight)

### Phase 5: Finalization (Week 5)

**Objectives:**
- Complete remaining service migrations
- Final validation and optimization
- Documentation and team training

**Activities:**
- Migrate remaining services (Weave GitOps, LocalStack, etc.)
- Performance optimization and monitoring
- Team training and documentation updates
- Deprecate old hardcoded configurations

---

## Environment-Specific Optimizations

### Development Environment (Cost-Optimized)

**Resource Strategy:** Minimize costs while maintaining functionality

```bash
# Development overrides (clusters/stages/dev/clusters/services-amer/environment.env)
CLUSTER_NAME=services-amer-dev
ENVIRONMENT=development

# Redis - Single node for development
REDIS_REPLICA_COUNT=1
REDIS_MASTER_MEMORY_REQUEST=128Mi
REDIS_MASTER_MEMORY_LIMIT=256Mi
REDIS_STORAGE_SIZE=4Gi

# Loki - Reduced resources and retention
LOKI_MEMORY_REQUEST=256Mi
LOKI_MEMORY_LIMIT=512Mi
LOKI_STORAGE_SIZE=5Gi
LOKI_RETENTION_PERIOD=168h  # 7 days

# PostgreSQL - Single instance
POSTGRESQL_INSTANCES=1
POSTGRESQL_STORAGE_SIZE=10Gi
POSTGRESQL_MEMORY_LIMIT=512Mi

# General development settings
DEFAULT_MEMORY_REQUEST=64Mi
DEFAULT_CPU_REQUEST=50m
```

### Production Environment (Performance-Optimized)

**Resource Strategy:** Maximize performance and availability

```bash
# Production overrides (clusters/stages/prod/clusters/services-amer/environment.env)
CLUSTER_NAME=services-amer-prod
ENVIRONMENT=production

# Redis - High availability configuration
REDIS_REPLICA_COUNT=2
REDIS_MASTER_MEMORY_REQUEST=512Mi
REDIS_MASTER_MEMORY_LIMIT=1Gi
REDIS_STORAGE_SIZE=16Gi

# Loki - Production performance and retention
LOKI_MEMORY_REQUEST=1Gi
LOKI_MEMORY_LIMIT=2Gi
LOKI_STORAGE_SIZE=50Gi
LOKI_RETENTION_PERIOD=720h  # 30 days

# PostgreSQL - High availability cluster
POSTGRESQL_INSTANCES=3
POSTGRESQL_STORAGE_SIZE=100Gi
POSTGRESQL_MEMORY_LIMIT=2Gi

# General production settings
DEFAULT_MEMORY_REQUEST=256Mi
DEFAULT_CPU_REQUEST=100m
```

---

## Migration Strategy

### Zero-Downtime Migration Approach

**Phase A: Infrastructure Preparation**
1. Deploy configuration infrastructure (ConfigMaps) without changing applications
2. Validate that all variables are correctly populated
3. Test variable substitution with dry-run deployments

**Phase B: Application Migration**
1. Update HelmRelease files to use variables (maintaining identical values)
2. Deploy one service at a time with health validation
3. Validate application functionality post-migration

**Phase C: Environment Optimization**
1. Adjust environment-specific values for optimal resource allocation
2. Validate performance improvements
3. Complete rollback testing

### Risk Mitigation Strategies

**Configuration Validation:**
- Pre-migration: Document all current values
- During migration: Validate variable substitution produces identical results
- Post-migration: Comprehensive application health checks

**Rollback Procedures:**
- Immediate rollback: Revert git commits and force Flux reconciliation
- Graduated rollback: Service-by-service rollback with dependency consideration
- Emergency rollback: Suspend Flux and manual kubectl application of known-good configs

### Validation Framework

**Pre-Migration Validation:**
```bash
#!/bin/bash
# scripts/validate-config-migration.sh

# 1. Extract current hardcoded values
kubectl get helmrelease -A -o yaml > /tmp/current-configs.yaml

# 2. Validate variable substitution
flux build kustomization services --path ./base/services \
  --kustomization-file ./clusters/stages/dev/clusters/services-amer/kustomization.yaml \
  --output /tmp/rendered-dev-configs/

# 3. Compare values to ensure identical results
./scripts/compare-config-values.sh /tmp/current-configs.yaml /tmp/rendered-dev-configs/

# 4. Validate all variables are defined
./scripts/check-undefined-variables.sh
```

**Post-Migration Validation:**
```bash
#!/bin/bash
# scripts/post-migration-health-check.sh

# 1. Wait for all services to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/managed-by=Helm \
  --all-namespaces --timeout=600s

# 2. Service-specific health checks
curl -f http://localhost:5678/healthz  # N8N
curl -f http://localhost:3030/api/health  # Grafana
redis-cli -h redis.redis.svc.cluster.local ping  # Redis

# 3. Resource utilization validation
kubectl top pods --all-namespaces > /tmp/post-migration-resources.txt
```

---

## Technical Implementation Details

### Base Configuration Extension

**Current base/services/environment.env:**
```bash
# Extend with comprehensive application variables
# Infrastructure services
TRAEFIK_CHART_VERSION=30.1.0
TRAEFIK_MEMORY_LIMIT=512Mi
TRAEFIK_CPU_LIMIT=1000m

REDIS_CHART_VERSION=20.3.0
REDIS_REPLICA_COUNT=2
REDIS_MASTER_MEMORY_LIMIT=512Mi
REDIS_STORAGE_SIZE=8Gi
REDIS_SENTINEL_TIMEOUT=30000

# Database services
POSTGRESQL_CHART_VERSION=15.5.0
POSTGRESQL_INSTANCES=1
POSTGRESQL_STORAGE_SIZE=20Gi
POSTGRESQL_MEMORY_LIMIT=1Gi

# Monitoring services
LOKI_CHART_VERSION=6.16.0
LOKI_MEMORY_LIMIT=1Gi
LOKI_STORAGE_SIZE=10Gi
LOKI_RETENTION_PERIOD=720h

PROMETHEUS_CHART_VERSION=25.8.0
PROMETHEUS_RETENTION_SIZE=10GiB
PROMETHEUS_MEMORY_LIMIT=2Gi

# Application services
N8N_CHART_VERSION=2.31.0
N8N_MEMORY_LIMIT=1Gi
N8N_STORAGE_SIZE=5Gi

TEMPORAL_CHART_VERSION=0.45.0
TEMPORAL_MEMORY_LIMIT=1Gi
TEMPORAL_STORAGE_SIZE=10Gi
```

### HelmRelease Migration Examples

**Redis Migration:**
```yaml
# Before (hardcoded)
spec:
  values:
    replica:
      replicaCount: 2
    master:
      resources:
        limits:
          memory: 512Mi
      persistence:
        size: 8Gi

# After (variable substitution)
spec:
  values:
    replica:
      replicaCount: ${REDIS_REPLICA_COUNT}
    master:
      resources:
        limits:
          memory: ${REDIS_MASTER_MEMORY_LIMIT}
      persistence:
        size: ${REDIS_STORAGE_SIZE}
```

**Loki Complex Configuration Migration:**
```yaml
# Before (hardcoded)
spec:
  values:
    loki:
      structuredConfig:
        limits_config:
          retention_period: 720h
        query_range:
          results_cache:
            cache:
              redis:
                expiration: 1h
                timeout: 500ms

# After (variable substitution)
spec:
  values:
    loki:
      structuredConfig:
        limits_config:
          retention_period: ${LOKI_RETENTION_PERIOD}
        query_range:
          results_cache:
            cache:
              redis:
                expiration: ${LOKI_CACHE_EXPIRATION}
                timeout: ${LOKI_CACHE_TIMEOUT}
```

---

## Production Environment Setup

### Directory Structure Creation

Since no prod environment exists, create the complete structure:

```bash
clusters/stages/prod/
├── README.md
├── base/
│   ├── cluster-vars-patch.yaml
│   └── kustomization.yaml
└── clusters/
    └── services-amer/
        ├── README.md
        ├── environment.env        # New: Prod-specific configuration
        ├── cluster-vars-patch.yaml
        ├── flux-system/
        │   ├── gotk-components.yaml
        │   ├── gotk-sync.yaml      # Tracks main branch
        │   └── kustomization.yaml
        └── kustomization.yaml
```

### Flux Configuration for Production

**Production Flux Sync (tracks main branch):**
```yaml
# clusters/stages/prod/clusters/services-amer/flux-system/gotk-sync.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m  # Less frequent sync for production
  ref:
    branch: main  # Production tracks main branch
  secretRef:
    name: flux-system
  url: ssh://git@github.com/jiwool0920/fleet-infra
```

---

## Success Metrics and Validation

### Technical Success Criteria

| Metric | Target | Measurement Method |
|--------|--------|--------------------|
| Zero-downtime migrations | 100% | Service availability monitoring |
| Configuration coverage | 100% | All hardcoded values extracted |
| Environment parity | Validated | Automated config comparison |
| Deployment time impact | <15% increase | Flux reconciliation metrics |
| Rollback success rate | 100% | Rollback procedure testing |

### Business Success Criteria

| Metric | Current | Target | Impact |
|--------|---------|--------|--------|
| New environment setup | N/A | 2 hours | Enable rapid scaling |
| Config change time | 30+ minutes | <5 minutes | 85% reduction |
| Environment consistency | Manual validation | Automated | Error elimination |
| Deployment confidence | Manual review | Automated validation | Risk reduction |

---

## Next Steps and Action Items

### Immediate Actions (This Week)

1. **Create prod environment structure** - Set up missing production environment
2. **Extend base configuration** - Add comprehensive application variables
3. **Create environment overlays** - Dev and prod specific optimizations
4. **Update kustomization files** - Enable ConfigMap generation and substitution

### Pilot Implementation (Next Week)

1. **Redis migration** - Start with straightforward resource configurations
2. **Loki migration** - Test complex cache configuration substitution
3. **Validation framework** - Establish testing and rollback procedures
4. **Documentation updates** - Update CLAUDE.md and team guidance

### Risk Mitigation Priorities

1. **Comprehensive testing** in development environment before any production changes
2. **Side-by-side validation** ensuring identical behavior pre/post migration
3. **Gradual rollout** one service at a time with health validation
4. **24/7 monitoring** during migration phases with immediate rollback capability

---

## Documentation and Training

### Documentation Updates Required

1. **CLAUDE.md**: New configuration management patterns and commands
2. **README.md**: Updated configuration management section
3. **Service READMEs**: Individual service configuration references
4. **Runbooks**: New deployment and configuration change procedures

### Team Enablement

1. **Configuration management training** for all team members
2. **Environment-specific optimization guidelines** for resource allocation
3. **Troubleshooting guides** for configuration-related issues
4. **Emergency procedures** for configuration rollbacks

---

This implementation plan provides a comprehensive roadmap for achieving the environment-specific configuration management goals outlined in GitHub Issue #5 while maintaining our successful fine-grained GitOps architecture and ensuring zero-downtime operations.
