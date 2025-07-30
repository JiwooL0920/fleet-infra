# Base Layer (Orchestration)

This directory contains the **orchestration layer** that coordinates the deployment of all services across the infrastructure, database, and application layers. It acts as the "traffic controller" for Flux CD operations.

## 🎼 Purpose

The base layer provides:
- **Deployment Orchestration** - Controls the order and timing of service deployments
- **Dependency Management** - Ensures services start only after their dependencies are ready
- **Environment Configuration** - Provides shared configuration variables across all layers
- **Flux Coordination** - Acts as the single entry point for GitOps operations

## 📦 Contents

### **Layer Orchestration Files**
- **`infrastructure.yaml`** - Flux Kustomization for infrastructure layer
  - Points to `./infrastructure/base`
  - No dependencies (deployed first)
  - 10-minute timeout for infrastructure services

- **`database.yaml`** - Flux Kustomization for database layer  
  - Points to `./database/base`
  - Depends on: `infrastructure` layer completion
  - 15-minute timeout for database cluster startup

- **`apps.yaml`** - Flux Kustomization for applications layer
  - Points to `./apps/base`  
  - Depends on: `database` layer completion
  - 10-minute timeout for application deployment

### **Configuration Management**
- **`environment.env`** - Base environment variables
  - Shared configuration across all services
  - Environment-agnostic default values
  - Used for variable substitution in manifests

- **`kustomization.yaml`** - Main orchestration configuration
  - Defines deployment order: infrastructure → database → apps
  - Creates `cluster-vars` ConfigMap from environment.env
  - Entry point for all Flux operations

### **Service Configuration**
- **`services/`** - Additional service configurations
  - Supplementary configurations that don't fit other layers
  - Cross-cutting concerns and shared resources

## 🔄 Deployment Flow

The orchestration ensures this exact deployment sequence:

```
1. infrastructure.yaml (Flux Kustomization)
   ↓ deploys all services in infrastructure/base/
   ✅ Traefik, LocalStack, External Secrets, Monitoring, GitOps

2. database.yaml (Flux Kustomization) - waits for infrastructure
   ↓ deploys all services in database/base/  
   ✅ CNPG Operator, PostgreSQL, Redis, pgAdmin4, RedisInsight

3. apps.yaml (Flux Kustomization) - waits for database
   ↓ deploys all services in apps/base/
   ✅ N8N, Temporal
```

## 🔗 How It Works

### **Orchestration Pattern:**
Instead of managing 15+ individual service deployments, the base layer groups them into 3 logical deployments with proper dependencies.

**Old Approach (Complex):**
```yaml
resources:
  - traefik.yaml      # 15+ individual 
  - postgres.yaml     # service files
  - redis.yaml        # with complex
  - n8n.yaml         # interdependencies
  # ... 11 more files
```

**New Approach (Simple):**
```yaml
resources:
  - infrastructure.yaml  # Deploys entire infrastructure layer
  - database.yaml       # Deploys entire database layer  
  - apps.yaml          # Deploys entire application layer
```

### **Environment Variable Substitution:**
All layers receive the `cluster-vars` ConfigMap containing:
- `CLUSTER_NAME` - Name of the current cluster
- `ENVIRONMENT` - Current environment (dev/prod)
- `REGION` - Cloud region configuration
- Custom variables from environment.env

### **Dependency Enforcement:**
Flux's `dependsOn` mechanism ensures:
- Database layer waits for infrastructure to be healthy
- Application layer waits for database to be healthy  
- No race conditions or startup failures

## 🎯 Benefits

### **Simplified Management:**
- **3 logical deployments** instead of 15+ individual services
- **Clear dependency chain** that's easy to understand
- **Centralized configuration** via environment variables

### **Reliability:**
- **Guaranteed startup order** prevents dependency failures
- **Health checks** ensure each layer is ready before proceeding
- **Proper timeouts** for each layer's complexity

### **Maintainability:**
- **Single source of truth** for deployment orchestration
- **Environment consistency** via shared configuration
- **Easy debugging** with clear layer boundaries

## 📝 Configuration Override

Environment-specific overrides are applied via:
- `clusters/stages/dev/cluster-vars-patch.yaml` - Development values
- `clusters/stages/prod/cluster-vars-patch.yaml` - Production values

These patches modify the `cluster-vars` ConfigMap with environment-specific values before deployment.

## 🔧 Usage

This directory is automatically processed by Flux CD. The typical flow:
1. Flux reads `base/kustomization.yaml`
2. Creates `cluster-vars` ConfigMap from `environment.env`
3. Applies environment-specific patches
4. Deploys infrastructure → database → apps in sequence
5. Each layer receives the final `cluster-vars` configuration

**Note:** This directory contains orchestration logic, not actual services. The services themselves are in their respective layer directories (`infrastructure/`, `database/`, `apps/`).