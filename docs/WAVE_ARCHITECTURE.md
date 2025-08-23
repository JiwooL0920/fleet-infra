# GitOps Wave-Based Deployment Architecture

## Overview

This document describes the comprehensive wave-based deployment architecture used in the fleet-infra repository. The system employs a 5-wave deployment strategy with strict dependency management to ensure reliable, one-shot cluster deployments.

## Wave Structure Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     WAVE DEPLOYMENT FLOW                        │
└─────────────────────────────────────────────────────────────────┘

Wave 1: Infrastructure Core (5m timeout)
├── LocalStack (AWS services emulation)
├── Traefik (Ingress controller) 
└── Secret-initializer (Creates initial secrets)
        ↓
Wave 2: Infrastructure Operators (10m timeout)
├── External Secrets Operator
├── CNPG Operator (PostgreSQL)
├── Crossplane (K8s control plane extension)
└── Metrics Server
        ↓
Wave 3: Infrastructure Configuration (5m timeout)
├── External Secrets Config (ClusterSecretStore)
├── Crossplane Providers (AWS provider)
├── Crossplane Config (Provider configuration)
└── Traefik Config (Middleware & auth)
        ↓
Wave 4: Parallel Deployment (10-15m timeout)
├── Infrastructure Monitoring
│   ├── Kube-Prometheus-Stack (Grafana, Prometheus, Alertmanager)
│   └── Weave GitOps
├── Infrastructure Logging
│   ├── Loki (depends on monitoring namespace + redis)
│   └── Promtail (depends on Loki)
├── Database Workloads
│   ├── PostgreSQL 3-node HA Cluster
│   └── Redis with authentication
└── Services
    ├── N8N (depends on PostgreSQL)
    └── Temporal (depends on PostgreSQL)
        ↓
Wave 5: Database UI (10m timeout)
├── pgAdmin4 (depends on PostgreSQL)
└── RedisInsight (depends on Redis)
```

## Repository Structure

```
fleet-infra/
├── apps/base/                    # Individual application configurations
│   ├── cloudnative-pg/          # PostgreSQL cluster & database definitions
│   ├── external-secrets-operator/ # Secret management operator
│   ├── kube-prometheus-stack/    # Monitoring stack (Grafana, Prometheus)
│   ├── loki/                    # Log aggregation
│   ├── n8n/                     # Workflow automation
│   ├── redis/                   # In-memory data store
│   ├── temporal/                # Workflow orchestration
│   └── traefik/                 # Ingress controller
│
├── base/                        # Wave orchestration layer
│   ├── infrastructure/          # Wave component definitions
│   │   ├── core/               # Wave 1 components
│   │   ├── operators/          # Wave 2 components  
│   │   ├── config/             # Wave 3 components
│   │   ├── monitoring/         # Wave 4 monitoring
│   │   └── logging/            # Wave 4 logging
│   ├── database/               # Database layer organization
│   │   ├── workloads/          # Core database services
│   │   └── ui/                 # Database management UIs
│   ├── services/               # Application services
│   └── *.yaml                  # Wave kustomization files
│
├── clusters/stages/             # Environment-specific configurations
│   └── dev/clusters/services-amer/ # Development environment
│       └── flux-system/        # Flux controllers (tracks develop branch)
│
└── docs/                       # Documentation
    └── WAVE_ARCHITECTURE.md   # This document
```

## Detailed Wave Dependencies

### Wave 1: Infrastructure Core
**Purpose**: Foundation services that everything else depends on
**Timeout**: 5 minutes
**Components**:
- **LocalStack**: AWS services emulation for development
- **Traefik**: Ingress controller and load balancer
- **Secret-initializer Job**: Creates initial secrets in LocalStack Secrets Manager

**Critical Dependencies**: None (foundation wave)

### Wave 2: Infrastructure Operators  
**Purpose**: Kubernetes operators that extend cluster capabilities
**Timeout**: 10 minutes
**Depends On**: infrastructure-core
**Components**:
- **External Secrets Operator**: Manages external secrets integration
- **CNPG Operator**: CloudNative PostgreSQL operator
- **Crossplane**: Kubernetes control plane extension
- **Metrics Server**: Cluster resource metrics

**Critical Dependencies**:
- LocalStack must be running for secret management
- CRDs must be installed before dependent resources

### Wave 3: Infrastructure Configuration
**Purpose**: Configuration resources that depend on operators
**Timeout**: 5 minutes  
**Depends On**: infrastructure-operators
**Components**:
- **External Secrets Config**: Creates ClusterSecretStore pointing to LocalStack
- **Crossplane Providers**: AWS provider for LocalStack integration
- **Crossplane Config**: AWS provider configuration with credentials
- **Traefik Config**: Middleware for dashboard authentication

**Critical Dependencies**:
- External Secrets Operator must be ready
- Crossplane must be ready
- Secret-initializer job must have completed

### Wave 4: Parallel Deployment
**Purpose**: Core services that can deploy simultaneously
**Timeout**: 10-15 minutes (varies by component)
**Depends On**: Various (see component details)

#### Infrastructure Monitoring
**Depends On**: infrastructure-operators
**Components**:
- **Kube-Prometheus-Stack**: Grafana, Prometheus, Alertmanager
- **Weave GitOps**: GitOps dashboard

#### Infrastructure Logging  
**Depends On**: infrastructure-monitoring
**Components**:
- **Loki**: Log aggregation (depends on monitoring namespace + Redis)
- **Promtail**: Log collection (depends on Loki)

#### Database Workloads
**Depends On**: infrastructure-operators  
**Timeout**: 15 minutes
**Components**:
- **PostgreSQL 3-node HA Cluster**: Primary database
- **Redis**: In-memory data store with authentication

#### Services
**Depends On**: infrastructure-config
**Components**:
- **N8N**: Workflow automation (requires PostgreSQL)
- **Temporal**: Workflow orchestration (requires PostgreSQL)

### Wave 5: Database UI
**Purpose**: Management interfaces for databases
**Timeout**: 10 minutes
**Depends On**: database-workloads
**Components**:
- **pgAdmin4**: PostgreSQL web interface
- **RedisInsight**: Redis web interface

## Critical Dependency Relationships

### Secret Management Flow
```
┌─────────────────────┐    ┌──────────────────────────┐    ┌─────────────────────┐
│ Secret-initializer  │───▶│ LocalStack Secrets       │───▶│ ClusterSecretStore  │
│ Job (Wave 1)        │    │ Manager                  │    │ (Wave 3)            │
└─────────────────────┘    └──────────────────────────┘    └─────────────────────┘
                                                                       │
                           ┌─────────────────────┐                    │
                           │ External Secrets    │◀───────────────────┘
                           │ Operator (Wave 2)   │
                           └─────────────────────┘
                                       │
                                       ▼
                           ┌─────────────────────┐    ┌─────────────────────┐
                           │ ExternalSecret      │───▶│ Kubernetes Secret   │
                           │ Resources           │    │ (in namespace)      │
                           └─────────────────────┘    └─────────────────────┘
                                       │                         │
                                       ▼                         ▼
                           ┌─────────────────────┐    ┌─────────────────────┐
                           │ Applications        │    │ Pod Environment     │
                           │ (Wave 4+)           │    │ Variables           │
                           └─────────────────────┘    └─────────────────────┘
```

### Database Dependencies
```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ CNPG Operator       │───▶│ PostgreSQL Cluster  │───▶│ Database Applications│
│ (Wave 2)            │    │ (Wave 4)            │    │ (Wave 4+)           │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
                                       │                         │
                                       ▼                         │
                           ┌─────────────────────┐               │
                           │ Auto-generated      │               │
                           │ DB Secrets          │               │
                           └─────────────────────┘               │
                                                                 │
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Database Applications                                    │
├─────────────────────┬─────────────────────┬─────────────────────┬─────────┤
│ N8N                 │ Temporal            │ pgAdmin4           │ Others  │
│ (appdb database)    │ (temporal DBs)      │ (admin interface)   │         │
└─────────────────────┴─────────────────────┴─────────────────────┴─────────┘
```

### Namespace and CRD Dependencies
```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ Traefik Helm        │───▶│ Traefik CRDs        │───▶│ Traefik Middleware  │
│ Release (Wave 1)    │    │ Available           │    │ Resources (Wave 3)  │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘

┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ Kube-Prometheus     │───▶│ Monitoring          │───▶│ Grafana ExternalSecret│
│ Stack (Wave 4)      │    │ Namespace           │    │ (Wave 4)            │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘

┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ External Secrets    │───▶│ ExternalSecret CRDs │───▶│ ExternalSecret      │
│ Operator (Wave 2)   │    │ Available           │    │ Resources (Wave 3+) │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

## Recent Critical Fixes Applied

### 1. Traefik CRD Chicken-and-Egg Problem
**Issue**: Traefik Middleware resources were being applied before Traefik CRDs existed
**Solution**: 
- Separated Traefik Helm release (Wave 1) from configuration (Wave 3)
- Created `traefik-config` separate from `traefik` application
**Files Changed**:
- `apps/base/traefik/kustomization.yaml` - Removed middleware and externalsecret
- `apps/base/traefik-config/` - New directory with CRD-dependent resources

### 2. Missing ExternalSecret References
**Issue**: Services failing with `CreateContainerConfigError` due to missing secrets
**Solution**: Added missing `externalsecret.yaml` to kustomization files
**Files Fixed**:
- `apps/base/loki/kustomization.yaml`
- `apps/base/n8n/kustomization.yaml` 
- `apps/base/temporal/kustomization.yaml`

### 3. Secret-initializer Job Failures
**Issue**: Job failing due to missing `openssl` and `python3` in aws-cli container
**Solution**: Replaced with shell-based htpasswd generation using available tools
**File Changed**: `apps/base/infrastructure/secret-init-job.yaml`

### 4. Wave Dependency Timing
**Issue**: Services starting before required dependencies were ready
**Solutions**:
- Added Redis dependency to Loki: `dependsOn: [kube-prometheus-stack, redis]`
- Fixed infrastructure-monitoring dependency from `infrastructure-core` to `infrastructure-operators`

### 5. ClusterSecretStore Dependency Chain
**Issue**: ExternalSecrets failing because ClusterSecretStore didn't exist
**Solution**: Ensured `external-secrets-config` kustomization was properly reconciled
**Root Cause**: Wave 3 dependencies weren't being resolved automatically

## Troubleshooting Common Issues

### Secret Sync Failures
**Symptoms**: 
- Pods stuck in `CreateContainerConfigError`
- ExternalSecret shows `SecretSyncedError`

**Diagnosis**:
```bash
# Check if ClusterSecretStore exists and is Ready
kubectl get clustersecretstore

# Check ExternalSecret status
kubectl get externalsecret -A

# Check if secrets exist in LocalStack
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets
```

**Resolution**:
```bash
# Force sync ExternalSecret
kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s)

# Check secret creation
kubectl get secret <secret-name> -n <namespace>
```

### Wave Dependency Stuck
**Symptoms**:
- Kustomizations show "dependency not ready"
- Wave appears stuck despite dependencies being True

**Diagnosis**:
```bash
# Check dependency chain status
flux get kustomizations

# Check specific kustomization details
kubectl describe kustomization <name> -n flux-system
```

**Resolution**:
```bash
# Force reconcile stuck wave
flux reconcile kustomization <name>

# If source is stale, update it
flux reconcile source git flux-system
```

### CRD Timing Issues
**Symptoms**:
- Resources can't be created due to missing CRDs
- "no matches for kind" errors

**Resolution**:
1. Ensure operators are in earlier waves than CRD usage
2. Use `dependsOn` to enforce proper timing
3. Separate Helm releases from CRD-dependent configuration

### Pod Startup Dependencies
**Symptoms**:
- Services can't connect to databases
- Authentication failures

**Diagnosis**:
```bash
# Check if required services are ready
kubectl get pods --all-namespaces | grep -v Running

# Check service dependencies
kubectl describe pod <pod-name> -n <namespace>
```

**Resolution**:
1. Verify database clusters are ready before dependent services
2. Ensure secrets are available in correct namespaces
3. Check service-to-service networking

## Best Practices for Modifications

### Adding New Services
1. **Determine Wave Placement**:
   - Wave 1: Only for foundation infrastructure
   - Wave 2: Kubernetes operators only
   - Wave 3: Configuration resources only
   - Wave 4: Application services and databases
   - Wave 5: UI applications depending on databases

2. **Configure Dependencies**:
   - Use `dependsOn` to specify wave dependencies
   - Add service-level dependencies within waves
   - Consider namespace creation dependencies

3. **Secret Management**:
   - Add secrets to `secret-init-job.yaml` if needed
   - Create corresponding ExternalSecret resources
   - Include ExternalSecret in kustomization.yaml

### Modifying Wave Structure
1. **Never Remove Dependencies**: Only add, don't remove existing `dependsOn`
2. **Test Dependency Changes**: Recreate cluster to verify one-shot deployment
3. **Consider Timing**: Adjust timeouts for complex services (15m for databases)
4. **Namespace Dependencies**: Ensure namespaces exist before resources using them

### Environment Separation
- **Development**: Tracks `develop` branch → `clusters/stages/dev/`
- **Production**: Would track `main` branch → `clusters/stages/prod/`
- Use `cluster-vars-patch.yaml` for environment-specific overrides
- Keep base configurations environment-agnostic

## Performance and Resource Considerations

### Wave Timeouts
- **Wave 1 (Core)**: 5m - Lightweight services
- **Wave 2 (Operators)**: 10m - Operator installations
- **Wave 3 (Config)**: 5m - Configuration resources  
- **Wave 4 (Applications)**: 10-15m - Heavy services, databases get 15m
- **Wave 5 (UI)**: 10m - User interfaces

### Resource Allocation
- **PostgreSQL**: 3-node cluster with resource limits
- **Monitoring Stack**: Prometheus (2Gi memory), Grafana (512Mi memory)
- **Loki**: 1Gi memory limit with Redis caching
- **Applications**: Conservative defaults (256Mi-512Mi memory)

### Parallelization
- Wave 4 components can deploy simultaneously after Wave 3 completes
- Database workloads and services run in parallel
- Individual services within waves have specific dependencies (e.g., Loki → Redis)

## Monitoring and Observability

### Deployment Monitoring
```bash
# Overall status
flux get kustomizations

# Component health
kubectl get helmrelease --all-namespaces

# Pod status
kubectl get pods --all-namespaces

# Failed resources
kubectl get pods --all-namespaces | grep -v Running
```

### Key Metrics
- **Deployment Time**: Full cluster deployment typically 15-20 minutes
- **Success Rate**: One-shot deployment should succeed reliably
- **Resource Usage**: Monitor memory and CPU during deployment waves
- **Dependency Resolution**: Track wave progression timing

---

*This documentation is maintained alongside the fleet-infra repository and should be updated when architectural changes are made.*