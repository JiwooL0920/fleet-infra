# Service Dependency Documentation

This document provides a comprehensive overview of the Kubernetes resource deployment order and dependencies in the fleet-infra GitOps repository. The infrastructure uses a wave-based deployment strategy managed by Flux CD for optimal startup performance and reliability.

## Overview

The deployment architecture follows a **5-wave dependency system** designed for enterprise-grade reliability and parallel deployment where possible. Each wave represents a logical grouping of services with specific dependency requirements and timeout configurations.

## Wave-Based Deployment Architecture

### Wave 1: Infrastructure Core (Foundation)
**Timeout: 5 minutes | Dependency: None | Parallelization: Sequential**

```
┌─────────────────────────────────────────────────────────────┐
│                      WAVE 1: INFRASTRUCTURE CORE           │
│                        (Foundation Layer)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────────────────────────┐    │
│  │   Traefik   │    │          LocalStack             │    │
│  │   (Ingress  │    │    (AWS Services Emulation)     │    │
│  │ Controller) │    │  - S3 (PostgreSQL backups)     │    │
│  │             │    │  - Secrets Manager (External    │    │
│  │             │    │    Secrets integration)        │    │
│  └─────────────┘    └─────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- **Traefik**: Ingress controller and load balancer - critical networking foundation
- **LocalStack**: Local AWS services emulation for development (S3, Secrets Manager)

**Why Wave 1:** These are foundational services that all other components depend on for networking and cloud services emulation.

### Wave 2: Infrastructure Operators
**Timeout: 10 minutes | Dependency: Wave 1 Complete | Parallelization: Sequential**

```
┌─────────────────────────────────────────────────────────────┐
│                  WAVE 2: INFRASTRUCTURE OPERATORS          │
│                      (Management Layer)                    │
├─────────────────────────────────────────────────────────────┤
│                        dependsOn: Wave 1                   │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │    CNPG Operator        │  │ External Secrets        │  │
│  │                         │  │      Operator           │  │
│  │ - Manages PostgreSQL    │  │                         │  │
│  │   clusters              │  │ - Syncs secrets from    │  │
│  │ - Handles HA, backups   │  │   external systems      │  │
│  │ - Resource lifecycle    │  │ - LocalStack integration│  │
│  │                         │  │ - ClusterSecretStore    │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- **CNPG Operator**: CloudNative PostgreSQL operator for database lifecycle management
- **External Secrets Operator**: Manages external secrets integration and synchronization

**Why Wave 2:** Kubernetes operators must be installed and ready before they can manage custom resources in subsequent waves.

### Wave 3: Infrastructure Configuration
**Timeout: 5 minutes | Dependency: Wave 2 Complete | Parallelization: Sequential**

```
┌─────────────────────────────────────────────────────────────┐
│               WAVE 3: INFRASTRUCTURE CONFIGURATION         │
│                      (Configuration Layer)                 │
├─────────────────────────────────────────────────────────────┤
│                        dependsOn: Wave 2                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            Configuration Resources                  │   │
│  │                                                     │   │
│  │ - Namespace configurations                          │   │
│  │ - ConfigMaps and base settings                      │   │
│  │ - Network policies                                  │   │
│  │ - Resource quotas                                   │   │
│  │ - Service accounts and RBAC                        │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- Namespace configurations and base settings
- ConfigMaps, service accounts, and RBAC policies
- Network policies and resource quotas

**Why Wave 3:** Configuration must be in place before workloads can be deployed.

### Wave 4: Parallel Deployment (Two Concurrent Categories)
**Timeout: Variable (10-15 minutes) | Dependency: Various | Parallelization: Concurrent**

Wave 4 enables maximum deployment efficiency through parallel execution of independent categories:

#### Wave 4a: Infrastructure Monitoring
**Timeout: 10 minutes | Dependency: Wave 1 Complete**

```
┌─────────────────────────────────────────────────────────────┐
│              WAVE 4a: INFRASTRUCTURE MONITORING            │
│                     (Observability Layer)                  │
├─────────────────────────────────────────────────────────────┤
│                       dependsOn: Wave 1                    │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │ Kube-Prometheus-Stack   │  │     Weave GitOps        │  │
│  │                         │  │                         │  │
│  │ - Prometheus            │  │ - GitOps dashboard      │  │
│  │ - Grafana               │  │ - Flux management UI    │  │
│  │ - Alertmanager          │  │ - Application status    │  │
│  │ - Node Exporter         │  │ - Reconciliation view   │  │
│  │ - Kube State Metrics    │  │                         │  │
│  │                         │  │                         │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Wave 4b: Database Workloads  
**Timeout: 15 minutes | Dependency: Wave 2 Complete**

```
┌─────────────────────────────────────────────────────────────┐
│                WAVE 4b: DATABASE WORKLOADS                 │
│                      (Data Layer)                          │
├─────────────────────────────────────────────────────────────┤
│                       dependsOn: Wave 2                    │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │   PostgreSQL Cluster    │  │         Redis           │  │
│  │                         │  │                         │  │
│  │ - 3-node HA cluster     │  │ - In-memory data store  │  │
│  │ - Auto backups to S3    │  │ - Authentication via    │  │
│  │ - Databases:            │  │   External Secrets      │  │
│  │   • appdb              │  │ - Session storage       │  │
│  │   • temporal           │  │ - Caching layer         │  │
│  │   • temporal_visibility │  │                         │  │
│  │                         │  │                         │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Wave 4c & 5: Database-Dependent Services (Parallel After Wave 4b)
**Timeout: 10 minutes | Dependency: Wave 4b Complete | Parallelization: Concurrent**

After Wave 4b (Database Workloads) is complete, both application services and database UI tools can deploy in parallel:

#### Application Services (Wave 4c)
```
┌─────────────────────────────────────────────────────────────┐
│                   APPLICATION SERVICES                     │
│                    (Business Logic Layer)                  │
├─────────────────────────────────────────────────────────────┤
│                       dependsOn: Wave 4b                   │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │          N8N            │  │       Temporal          │  │
│  │                         │  │                         │  │
│  │ - Workflow automation   │  │ - Workflow orchestration│  │
│  │ - PostgreSQL backend    │  │ - PostgreSQL backend    │  │
│  │ - Web UI interface      │  │ - Temporal UI           │  │
│  │ - API integrations      │  │ - Durable workflows     │  │
│  │                         │  │ - Activity execution    │  │
│  │                         │  │                         │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Database UI Tools (Wave 5)

```
┌─────────────────────────────────────────────────────────────┐
│                    DATABASE UI TOOLS                       │
│                    (Administration Layer)                  │
├─────────────────────────────────────────────────────────────┤
│                     dependsOn: Wave 4b                     │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │       pgAdmin4          │  │     RedisInsight        │  │
│  │                         │  │                         │  │
│  │ - PostgreSQL admin UI   │  │ - Redis management UI   │  │
│  │ - Database management   │  │ - Key-value browser     │  │
│  │ - Query execution       │  │ - Performance metrics   │  │
│  │ - User management       │  │ - Memory analysis       │  │
│  │ - Connection pooling    │  │ - Query profiling       │  │
│  │                         │  │                         │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- **pgAdmin4**: Web-based PostgreSQL database administration tool
- **RedisInsight**: Web-based Redis database administration and monitoring tool

**Why Parallel with Wave 4c:** UI tools only depend on databases being operational, not on application services. They can start as soon as Wave 4b completes.

## Complete Dependency Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              COMPLETE DEPENDENCY FLOW                                   │
└─────────────────────────────────────────────────────────────────────────────────────────┘

WAVE 1 (Sequential, 5m timeout)
┌─────────────┐    ┌─────────────┐
│   Traefik   │    │ LocalStack  │
└──────┬──────┘    └──────┬──────┘
       │                  │
       └──────────┬───────┘
                  │
                  ▼
WAVE 2 (Sequential, 10m timeout, depends on Wave 1)
┌──────────────────┐    ┌──────────────────────┐
│  CNPG Operator   │    │ External Secrets Op  │
└─────────┬────────┘    └───────────┬──────────┘
          │                         │
          └─────────┬───────────────┘
                    │
                    ▼
WAVE 3 (Sequential, 5m timeout, depends on Wave 2)
┌─────────────────────────────────────┐
│    Infrastructure Configuration     │
└─────────────────┬───────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
WAVE 4 (Parallel deployment categories)
┌─────────────┐ ┌─────────────┐ 
│Monitoring   │ │Database     │ 
│(deps: W1)   │ │Workloads    │ 
│10m timeout  │ │(deps: W2)   │ 
│             │ │15m timeout  │ 
│- Prometheus │ │- PostgreSQL │ 
│- Grafana    │ │- Redis      │ 
│- WeaveGitOps│ │             │ 
└─────────────┘ └──────┬──────┘ 
                       │
                       ├─────────────────┐
                       ▼                 ▼
                ┌─────────────────┐ ┌─────────────────┐
                │Application      │ │Database UI      │
                │Services         │ │Tools            │
                │(deps: W4b)      │ │(deps: W4b)      │
                │10m timeout      │ │10m timeout      │
                │- N8N            │ │- pgAdmin4       │
                │- Temporal       │ │- RedisInsight   │
                │                 │ │                 │
                └─────────────────┘ └─────────────────┘
                
                Wave 4c & 5 deploy in parallel after W4b
```

## Flux CD Kustomization Dependencies

### Primary Kustomization Chain
```yaml
# base/kustomization.yaml resource order
resources:
  - infrastructure-core.yaml        # Wave 1
  - infrastructure-operators.yaml   # Wave 2 (depends on Wave 1)
  - infrastructure-config.yaml      # Wave 3 (depends on Wave 2)
  - infrastructure-monitoring.yaml  # Wave 4a (depends on Wave 1)
  - database-workloads.yaml        # Wave 4b (depends on Wave 2)
  - services.yaml                   # Wave 4c (depends on Wave 3)
  - database-ui.yaml               # Wave 5 (depends on Wave 4b)
```

### Detailed Flux Dependencies
```yaml
# infrastructure-operators.yaml
dependsOn:
  - name: infrastructure-core

# infrastructure-config.yaml  
dependsOn:
  - name: infrastructure-operators

# infrastructure-monitoring.yaml
dependsOn:
  - name: infrastructure-core

# database-workloads.yaml
dependsOn:
  - name: infrastructure-operators

# services.yaml
dependsOn:
  - name: database-workloads

# database-ui.yaml
dependsOn:
  - name: database-workloads
```

## Service-Level Dependencies

### Database Dependencies
- **PostgreSQL Cluster**: Requires CNPG Operator + LocalStack (S3 backups)
- **Redis**: Requires External Secrets Operator (password management)

### Application Dependencies
- **N8N**: Requires PostgreSQL cluster (database backend)
- **Temporal**: Requires PostgreSQL cluster (workflow persistence)
- **pgAdmin4**: Requires PostgreSQL cluster + External Secrets (credentials)
- **RedisInsight**: Requires Redis cluster

### Infrastructure Dependencies
- **External Secrets**: Requires LocalStack (Secrets Manager simulation)
- **All Services**: Require Traefik (ingress controller)
- **Monitoring Stack**: Independent of databases (can start in parallel)

## Resource Types and Timing

### Critical Path Analysis
```
Longest deployment path:
Wave 1 (5m) → Wave 2 (10m) → Wave 4b (15m) → Wave 4c & 5 (10m parallel)
Total: 40 minutes maximum
```

### Parallel Optimization
```
Optimized parallel paths:
Path A: Wave 1 → Wave 4a (Monitoring) = 15 minutes
Path B: Wave 1 → Wave 2 → Wave 4b → Wave 4c (Services) = 40 minutes (critical path)
Path C: Wave 1 → Wave 2 → Wave 4b → Wave 5 (DB UI) = 40 minutes (same timing as Path B)
```

### Timeout Configuration
- **Wave 1**: 5 minutes (fast networking setup)
- **Wave 2**: 10 minutes (operator installation)  
- **Wave 3**: 5 minutes (configuration setup)
- **Wave 4a**: 10 minutes (monitoring tools)
- **Wave 4b**: 15 minutes (database clusters - most time-intensive)
- **Wave 4c**: 10 minutes (application services)
- **Wave 5**: 10 minutes (UI tools)

## Health Check and Readiness

### Flux Wait Conditions
All Kustomizations use `wait: true` which means:
- Each wave waits for all resources to be ready before proceeding
- Health checks are performed on Deployments, StatefulSets, and Pods
- HelmReleases must reach "Ready" status
- Custom resources (PostgreSQL clusters) must pass operator health checks

### Startup Verification
Use the provided script to verify proper startup order:
```bash
make verify-startup
# OR
./scripts/verify-startup.sh
```

### Service Health Endpoints
When port-forwarding is active:
- **Traefik**: http://localhost:8080 (dashboard)
- **LocalStack**: http://localhost:4566/_localstack/health
- **PostgreSQL**: localhost:5432 (database connection)
- **Redis**: localhost:6379 (redis-cli connection)
- **N8N**: http://localhost:5678
- **Temporal**: http://localhost:8090
- **Grafana**: http://localhost:3030
- **pgAdmin4**: http://localhost:8080
- **RedisInsight**: http://localhost:8001

## Troubleshooting Dependency Issues

### Common Dependency Problems
1. **Operator Not Ready**: Wave 2 services fail because operators aren't fully initialized
2. **Database Connection**: Wave 4c/5 services fail because databases aren't accepting connections
3. **Secret Sync**: Services fail because External Secrets hasn't synced credentials
4. **Network Policies**: Services fail because Traefik ingress isn't ready

### Debugging Commands
```bash
# Check Flux status across all waves
flux get kustomizations

# Check specific wave status
kubectl get kustomization infrastructure-operators -n flux-system -o yaml

# Check operator readiness
kubectl get pods -n cnpg-system
kubectl get pods -n external-secrets-system

# Check database cluster status  
kubectl get cluster -n cnpg-system
kubectl get pods -n cnpg-system

# Check secret synchronization
kubectl get externalsecrets --all-namespaces
kubectl get secrets --all-namespaces | grep -E "(pgadmin|redis)"

# Force reconciliation if stuck
flux reconcile kustomization <wave-name>
```

### Recovery Procedures
1. **Stuck Wave**: Force reconciliation of the specific wave
2. **Database Issues**: Check CNPG operator logs and cluster status
3. **Secret Issues**: Verify LocalStack health and External Secrets operator
4. **Network Issues**: Ensure Traefik is ready and ingress rules are applied

## Environment-Specific Considerations

### Development Environment
- Faster sync intervals (1 minute vs 10 minutes for production)
- Uses LocalStack for AWS services simulation
- More permissive timeout values for slower startup

### Production Environment  
- Longer sync intervals for stability (10 minutes)
- Real AWS services instead of LocalStack
- Stricter resource limits and security policies
- Separate branch tracking (`main` vs `develop`)

## Best Practices

### Adding New Services
1. **Identify Dependencies**: Determine which wave your service belongs in
2. **Set Appropriate Timeouts**: Database services need longer timeouts
3. **Use Category Dependencies**: Depend on wave-level kustomizations, not individual services
4. **Test Startup Order**: Verify dependencies work in development environment

### Modifying Dependencies
1. **Understand Impact**: Changes to lower waves affect all subsequent waves
2. **Test Thoroughly**: Use `flux diff` to preview changes
3. **Monitor Reconciliation**: Watch for dependency loops or circular references
4. **Document Changes**: Update this document when dependency structure changes

### Performance Optimization
1. **Maximize Parallelization**: Keep wave 4 services independent when possible
2. **Optimize Timeouts**: Set realistic but not excessive timeout values
3. **Health Check Tuning**: Ensure readiness probes are accurate but not too strict
4. **Resource Limits**: Prevent resource contention during parallel deployment

---

*This document is maintained as part of the fleet-infra GitOps repository. Update when adding new services or modifying deployment dependencies.*