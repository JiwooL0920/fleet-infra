# Services AMER Infrastructure with Flux GitOps

This repository contains the GitOps configuration for the `services-amer` Kubernetes clusters across multiple environments, bootstrapped with Flux CD for continuous deployment.

## Overview

The `services-amer` clusters are set up using [Flux CD](https://fluxcd.io/), a set of continuous and progressive delivery solutions for Kubernetes. This repository implements a multi-environment GitOps workflow where Git branches serve as the source of truth for different environments.

## 🚀 Current Infrastructure

### Deployed Applications

| Application | Status | Version | Database | Purpose |
|-------------|--------|---------|----------|----------|
| **CloudNative PG** | ✅ Running | v0.24.0 | - | PostgreSQL operator and 3-node HA cluster |
| **N8N** | ✅ Running | v1.0.10 | PostgreSQL | Workflow automation engine |
| **Traefik** | ✅ Running | v25.0.0 | - | Ingress controller and load balancer |
| **Flux** | ✅ Running | v2.5.1 | - | GitOps continuous deployment |

### Database Infrastructure

- **PostgreSQL Cluster**: 3-node HA setup with automatic failover
- **Databases**: `app`, `n8n`, `temporal`, `temporal_visibility`
- **Storage**: 5GB per instance with persistent volumes
- **Security**: Auto-generated secure passwords, no hardcoded secrets

### Network & Connectivity

- **Ingress**: Traefik handling HTTP/HTTPS traffic
- **Services**: All apps exposed via ClusterIP
- **DNS**: Internal cluster DNS for service discovery
- **Port Forwarding**: Available for local development access

## Multi-Environment Architecture

### Environment Strategy
- **Development (dev)**: Tracks the `develop` branch
- **Production (prod)**: Tracks the `main` branch

### Branch Workflow
```
develop ──────────► Dev Environment
    │
    │ (merge after testing)
    ▼
main ─────────────► Prod Environment
```

## Directory Structure

```
├── apps/
│   └── base/                     # Base application configurations
│       ├── cnpg/                 # CloudNative PostgreSQL
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       ├── n8n/                  # N8N Workflow Engine
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       └── traefik/              # Traefik Ingress Controller
│           ├── helmrelease.yaml
│           └── kustomization.yaml
├── base/
│   ├── kustomization.yaml        # Base resource aggregation
│   └── services/                 # Service configurations
├── clusters/
│   └── stages/                   # Environment grouping
│       ├── dev/                  # Development environment
│       │   └── clusters/         # Clusters in dev
│       │       └── services-amer/ # Dev cluster configuration
│       │           └── flux-system/
│       │               ├── kustomization.yaml
│       │               ├── gotk-components.yaml
│       │               └── gotk-sync.yaml (tracks develop branch)
│       └── prod/                 # Production environment
│           └── clusters/         # Clusters in prod
│               └── services-amer/ # Prod cluster configuration
│                   └── flux-system/
│                       ├── kustomization.yaml
│                       ├── gotk-components.yaml
│                       └── gotk-sync.yaml (tracks main branch)
└── scripts/
    └── flux-bootstrap.sh         # Unified bootstrap script
```

## Bootstrap Process

### Dynamic Bootstrap Script

The `scripts/flux-bootstrap.sh` script automatically configures the correct branch and path based on the environment:

```bash
# Bootstrap development environment (develop branch)
scripts/flux-bootstrap.sh dev

# Bootstrap production environment (main branch)  
scripts/flux-bootstrap.sh prod
```

### Script Behavior

| Environment | Branch | Path |
|-------------|--------|------|
| `dev` | `develop` | `./clusters/stages/dev/clusters/services-amer` |
| `prod` | `main` | `./clusters/stages/prod/clusters/services-amer` |

### Usage Examples

```bash
# See usage help
scripts/flux-bootstrap.sh

# Bootstrap dev environment
scripts/flux-bootstrap.sh dev

# Bootstrap prod environment
scripts/flux-bootstrap.sh prod
```

## GitOps Workflow

### Development Workflow
1. **Feature Development**: Create feature branches from `develop`
2. **Testing**: Merge features into `develop` branch
3. **Auto-Deploy**: Flux automatically deploys `develop` to dev environment
4. **Validation**: Test changes in dev environment
5. **Promotion**: Merge `develop` to `main` for production release

### Production Deployment
1. **Release**: Merge tested `develop` branch to `main`
2. **Auto-Deploy**: Flux automatically deploys `main` to prod environment
3. **Monitoring**: Monitor production deployment

## Environment Configuration

### Development Environment
- **Branch**: `develop`
- **Sync Interval**: 1 minute (faster iteration)
- **Path**: `clusters/stages/dev/clusters/services-amer`
- **Purpose**: Testing and validation

### Production Environment  
- **Branch**: `main`
- **Sync Interval**: 10 minutes (stable releases)
- **Path**: `clusters/stages/prod/clusters/services-amer`
- **Purpose**: Live production workloads

## Kubernetes Resources Created

Each environment gets its own complete Flux installation with:

### Core Controllers
- **Source Controller**: Manages Git repositories and artifacts
- **Kustomize Controller**: Applies Kustomize configurations
- **Helm Controller**: Manages Helm releases
- **Notification Controller**: Handles events and notifications

### Security Features
- **RBAC**: Proper cluster and namespace-level permissions
- **Network Policies**: Restricted network access
- **Pod Security**: Non-root containers, read-only filesystems
- **SSH Authentication**: Secure Git repository access

## Cluster Setup

### Prerequisites
- Kind cluster named `services-amer` (for dev)
- Kind cluster named `services-amer-prod` (for prod, if running locally)
- GitHub personal access token
- Flux CLI installed

### Creating Clusters

```bash
# Create dev cluster
kind create cluster --name services-amer

# Create prod cluster (if testing locally)
kind create cluster --name services-amer-prod
```

### Bootstrap Environments

```bash
# Bootstrap development environment
scripts/flux-bootstrap.sh dev

# Switch to prod cluster context and bootstrap
kubectl config use-context kind-services-amer-prod
scripts/flux-bootstrap.sh prod
```

## Application Deployment

### Adding Applications

#### For Development
1. Create manifests in `clusters/stages/dev/clusters/services-amer/`
2. Commit to `develop` branch
3. Flux automatically deploys to dev cluster

#### For Production
1. Test changes in `develop` branch
2. Merge `develop` to `main` branch
3. Flux automatically deploys to prod cluster

### Example Application Structure
```
clusters/stages/
├── dev/clusters/services-amer/
│   ├── flux-system/           # Flux components
│   ├── namespaces/            # Namespace definitions
│   ├── applications/          # Application deployments
│   └── kustomization.yaml     # Root kustomization
└── prod/clusters/services-amer/
    ├── flux-system/           # Flux components  
    ├── namespaces/            # Namespace definitions
    ├── applications/          # Application deployments
    └── kustomization.yaml     # Root kustomization
```

## 🔗 Accessing Applications

### N8N Workflow Engine
```bash
# Port forward to access N8N UI
kubectl port-forward -n n8n svc/n8n 8080:80

# Then access: http://localhost:8080
```

### PostgreSQL Database
```bash
# Get database credentials
kubectl get secret postgresql-cluster-app -n cnpg-system -o jsonpath='{.data.username}' | base64 -d
kubectl get secret postgresql-cluster-app -n cnpg-system -o jsonpath='{.data.password}' | base64 -d

# Port forward to access database
kubectl port-forward -n cnpg-system svc/postgresql-cluster-rw 5432:5432

# Connect using psql
psql -h localhost -p 5432 -U app -d app
```

### Traefik Dashboard
```bash
# Port forward to access Traefik dashboard
kubectl port-forward -n traefik svc/traefik 9000:9000

# Then access: http://localhost:9000
```

## Useful Commands

### Environment Status
```bash
# Check Flux status
flux get all

# Check source synchronization
flux get sources git

# Check kustomizations
flux get kustomizations

# Check application health
kubectl get pods --all-namespaces
kubectl get helmrelease --all-namespaces
```

### Debugging
```bash
# View controller logs
kubectl logs -n flux-system -l app=source-controller
kubectl logs -n flux-system -l app=kustomize-controller

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Check events
kubectl get events -n flux-system --sort-by='.lastTimestamp'
```

### Branch Management
```bash
# Check current branch
git branch

# Switch to develop for dev changes
git checkout develop

# Merge develop to main for prod release
git checkout main
git merge develop
```

## Best Practices

### Development
- Always test in `develop` branch first
- Use pull requests for code review
- Validate changes in dev environment before promoting

### Production
- Only deploy tested and approved changes
- Use semantic versioning for releases
- Monitor deployments and rollback if needed

### Security
- Regularly update Flux components
- Review and rotate deploy keys
- Monitor for security vulnerabilities
- No hardcoded secrets in Git (uses `.env` files and auto-generated passwords)
- PostgreSQL credentials auto-generated and stored in Kubernetes secrets

## 🔐 Database Management

### PostgreSQL Cluster Health
```bash
# Check cluster status
kubectl get cluster -n cnpg-system

# Check individual pods
kubectl get pods -n cnpg-system

# View cluster details
kubectl describe cluster postgresql-cluster -n cnpg-system
```

### Database Operations
```bash
# List all databases
kubectl run pg-client -n cnpg-system --rm --restart=Never -it --image=postgres:16 -- \
  psql -h postgresql-cluster-rw -U app -d app -c "\l"

# Create new database
kubectl run pg-client -n cnpg-system --rm --restart=Never -it --image=postgres:16 -- \
  psql -h postgresql-cluster-rw -U app -d app -c "CREATE DATABASE myapp;"

# Backup database
kubectl run pg-client -n cnpg-system --rm --restart=Never -it --image=postgres:16 -- \
  pg_dump -h postgresql-cluster-rw -U app -d myapp > backup.sql
```

### N8N Database Migration
```bash
# Check N8N database connection
kubectl logs -n n8n deployment/n8n | grep -i database

# Verify N8N tables
kubectl run pg-client -n cnpg-system --rm --restart=Never -it --image=postgres:16 -- \
  psql -h postgresql-cluster-rw -U app -d n8n -c "\dt"
```

## Troubleshooting

### Common Issues
1. **Sync Failures**: Check Git repository access and SSH keys
2. **Branch Mismatch**: Ensure correct branch is specified in gotk-sync.yaml
3. **Path Errors**: Verify path configuration matches directory structure

### Environment-Specific Issues

#### Development Environment
- Check `develop` branch exists and has latest changes
- Verify dev cluster context is active

#### Production Environment  
- Ensure `main` branch contains tested changes
- Verify prod cluster context is active
- Check production-specific configurations

## 📊 Version Information

### Infrastructure Components
- **Flux Version**: v2.5.1
- **Kubernetes**: v1.33.1 (Kind cluster)
- **CloudNative PG**: v0.24.0 (PostgreSQL 16)
- **N8N**: v1.0.10 (Chart version)
- **Traefik**: v25.0.0

### Current Status
- **Cluster Health**: ✅ All nodes ready
- **Applications**: ✅ All deployments healthy
- **Database**: ✅ PostgreSQL 3-node HA cluster operational
- **GitOps**: ✅ Flux synced to latest commit
- **Security**: ✅ No hardcoded secrets in Git

### Compatibility
- **Kubernetes**: Supports 1.20+
- **Environments**: Development (develop branch), Production (main branch)
- **Database**: PostgreSQL 16 with CloudNative PG operator

## 🚀 Quick Start

### Access Applications
```bash
# N8N Workflow Engine
kubectl port-forward -n n8n svc/n8n 8080:80
# Open: http://localhost:8080

# PostgreSQL Database
kubectl port-forward -n cnpg-system svc/postgresql-cluster-rw 5432:5432
# Connect: psql -h localhost -p 5432 -U app -d app

# Traefik Dashboard  
kubectl port-forward -n traefik svc/traefik 9000:9000
# Open: http://localhost:9000
```

### Quick Health Check
```bash
# Check all applications
kubectl get pods --all-namespaces
kubectl get helmrelease --all-namespaces
kubectl get cluster -n cnpg-system
```

## Quick Reference

- **📋 [Workflow Guide](docs/WORKFLOW.md)**: Detailed environment workflow and safety guidelines
- **🔧 Scripts**: Use `scripts/flux-bootstrap.sh <env>` for environment setup
- **🛡️ Safety**: Pre-commit hooks prevent cross-environment mistakes
- **📊 Current Status**: All infrastructure components healthy and operational

---

**This multi-environment setup provides a robust GitOps foundation with proper separation between development and production while maintaining consistency and automation across environments.**
