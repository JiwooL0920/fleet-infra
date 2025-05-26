# Services AMER Infrastructure with Flux GitOps

This repository contains the GitOps configuration for the `services-amer` Kubernetes cluster, bootstrapped with Flux CD for continuous deployment.

## Overview

The `services-amer` cluster was set up using [Flux CD](https://fluxcd.io/), a set of continuous and progressive delivery solutions for Kubernetes. Flux enables GitOps workflows where the Git repository serves as the single source of truth for cluster configuration.

## Bootstrap Process

### What Happened

The cluster was bootstrapped using the script `scripts/flux-bootstrap.sh`, which executed the following Flux command:

```bash
flux bootstrap github \
  --owner=JiwooL0920 \
  --repository=fleet-infra \
  --branch=main \
  --path=./clusters/stages/dev/clusters/services-amer \
  --personal
```

### Bootstrap Process Details

1. **GitHub Integration**: Connected the local Kind cluster `services-amer` to this GitHub repository
2. **SSH Key Generation**: Created deploy keys for secure Git repository access
3. **Flux Installation**: Installed Flux controllers and CRDs in the `flux-system` namespace
4. **GitOps Setup**: Configured continuous synchronization between the Git repository and cluster state
5. **File Generation**: Created Kubernetes manifests in `clusters/stages/dev/clusters/services-amer/flux-system/`

## Directory Structure

```
├── clusters/
│   └── stages/                # Environment grouping
│       └── dev/               # Development environment
│           └── clusters/      # Clusters in this environment
│               └── services-amer/     # Cluster-specific configuration
│                   └── flux-system/   # Flux system components
│                       ├── kustomization.yaml    # Kustomize configuration
│                       ├── gotk-components.yaml  # Flux toolkit components
│                       └── gotk-sync.yaml        # Git sync configuration
└── scripts/
    └── flux-bootstrap.sh      # Bootstrap script
```

### Multi-Environment Structure

This repository follows a multi-environment structure that supports:

- **Environment Separation**: Different stages (dev, staging, prod) are clearly separated
- **Cluster Organization**: Multiple clusters per environment are supported
- **Scalability**: Easy to add new environments and clusters
- **Consistency**: Same structure across all environments

**Future Expansion Example**:
```
clusters/
├── stages/
│   ├── dev/
│   │   └── clusters/
│   │       ├── services-amer/
│   │       └── other-dev-cluster/
│   ├── staging/
│   │   └── clusters/
│   │       └── services-amer/
│   └── prod/
│       └── clusters/
│           └── services-amer/
```

## Kubernetes Resources Created

### Namespace
- **`flux-system`**: Dedicated namespace for all Flux components with appropriate security policies

### Core Controllers (Deployments)

#### 1. Source Controller (`source-controller`)
- **Image**: `ghcr.io/fluxcd/source-controller:v1.5.0`
- **Purpose**: Manages source repositories (Git, Helm, OCI)
- **Resources**: 50m CPU / 64Mi memory (requests), 1000m CPU / 1Gi memory (limits)
- **Features**:
  - Watches Git repositories for changes
  - Handles artifact storage and caching
  - Provides source artifacts to other controllers

#### 2. Kustomize Controller (`kustomize-controller`)
- **Image**: `ghcr.io/fluxcd/kustomize-controller:v1.5.1`
- **Purpose**: Applies Kustomize configurations to the cluster
- **Resources**: 100m CPU / 64Mi memory (requests), 1000m CPU / 1Gi memory (limits)
- **Features**:
  - Processes Kustomization resources
  - Applies manifests with proper ordering and dependencies
  - Handles garbage collection of orphaned resources

#### 3. Helm Controller (`helm-controller`)
- **Image**: `ghcr.io/fluxcd/helm-controller:v1.2.0`
- **Purpose**: Manages Helm releases
- **Resources**: 100m CPU / 64Mi memory (requests), 1000m CPU / 1Gi memory (limits)
- **Features**:
  - Deploys and upgrades Helm charts
  - Handles rollbacks and chart dependencies
  - Integrates with Helm repositories

#### 4. Notification Controller (`notification-controller`)
- **Image**: `ghcr.io/fluxcd/notification-controller:v1.5.0`
- **Purpose**: Handles events and notifications
- **Resources**: 100m CPU / 64Mi memory (requests), 1000m CPU / 1Gi memory (limits)
- **Features**:
  - Webhook receiver for external events
  - Alert management and forwarding
  - Integration with notification providers

### Custom Resource Definitions (CRDs)

Flux installed several CRDs to extend Kubernetes API:

#### Source CRDs
- **GitRepository**: Defines Git sources
- **HelmRepository**: Defines Helm chart repositories  
- **HelmChart**: Defines individual Helm charts
- **Bucket**: Defines S3-compatible storage sources
- **OCIRepository**: Defines OCI artifact sources

#### Kustomize CRDs
- **Kustomization**: Defines how to apply Kustomize configurations

#### Helm CRDs
- **HelmRelease**: Defines Helm release configurations

#### Notification CRDs
- **Provider**: Defines notification endpoints
- **Alert**: Defines alerting rules
- **Receiver**: Defines webhook receivers

### RBAC Configuration

#### Cluster Roles
- **`crd-controller-flux-system`**: Full access to Flux CRDs and core resources
- **`flux-edit-flux-system`**: Edit permissions aggregated to admin/edit roles
- **`flux-view-flux-system`**: View permissions aggregated to view role

#### Service Accounts
Individual service accounts for each controller:
- `source-controller`
- `kustomize-controller` 
- `helm-controller`
- `notification-controller`

### Network Policies

#### `allow-egress`
- Allows all egress traffic from flux-system pods
- Allows ingress between flux-system pods

#### `allow-scraping`
- Allows Prometheus scraping on port 8080
- Permits monitoring integration

#### `allow-webhooks`
- Allows webhook traffic to notification-controller
- Enables external webhook integration

### Resource Management

#### Resource Quota
- **`critical-pods-flux-system`**: Limits critical pods to 1000 in the namespace

#### Priority Classes
- All controllers run with `system-cluster-critical` priority class
- Ensures Flux components are protected during resource pressure

### Services

#### Internal Services
- **`source-controller`**: Internal API for source artifacts
- **`notification-controller`**: Internal event processing
- **`webhook-receiver`**: External webhook endpoint

### GitOps Synchronization

#### GitRepository Resource (`flux-system`)
```yaml
spec:
  interval: 1m0s          # Check for changes every minute
  ref:
    branch: main          # Watch the main branch
  url: ssh://git@github.com/JiwooL0920/fleet-infra
```

#### Kustomization Resource (`flux-system`)
```yaml
spec:
  interval: 10m0s         # Apply changes every 10 minutes
  path: ./clusters/stages/dev/clusters/services-amer  # Monitor this path in the repo
  prune: true             # Remove resources not in Git
```

## Security Features

### Pod Security
- **Non-root execution**: All containers run as non-root users
- **Read-only root filesystem**: Enhanced container security
- **Dropped capabilities**: Minimal required Linux capabilities
- **Security profiles**: Uses RuntimeDefault seccomp profiles

### Network Security
- Network policies restrict traffic flow
- TLS communication between components
- SSH key-based Git authentication

## Monitoring and Observability

### Metrics
- All controllers expose Prometheus metrics on port 8080
- Health check endpoints available on port 9440
- Structured JSON logging enabled

### Health Checks
- Liveness probes ensure container health
- Readiness probes control traffic routing
- Graceful shutdown handling

## Next Steps

With Flux bootstrapped, you can now:

1. **Add Applications**: Create Kustomization or HelmRelease resources in `clusters/stages/dev/clusters/services-amer/`
2. **Configure Sources**: Add GitRepository or HelmRepository resources for additional sources
3. **Set Up Monitoring**: Deploy monitoring stack (Prometheus, Grafana) via Flux
4. **Add Alerts**: Configure notification providers and alerts for deployment events
5. **Multi-tenancy**: Create additional namespaces and RBAC for team separation

## Useful Commands

```bash
# Check Flux status
flux get all

# Check source synchronization
flux get sources git

# Check kustomizations
flux get kustomizations

# View logs
kubectl logs -n flux-system -l app=source-controller
kubectl logs -n flux-system -l app=kustomize-controller

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

## Troubleshooting

### Common Issues
1. **Sync failures**: Check Git repository access and SSH keys
2. **Apply failures**: Review RBAC permissions and resource conflicts
3. **Performance**: Adjust resource limits based on cluster size

### Debug Commands
```bash
# Check Flux installation
flux check

# Verify Git access
flux get sources git flux-system

# Check events
kubectl get events -n flux-system --sort-by='.lastTimestamp'
```

## Version Information

- **Flux Version**: v2.5.1
- **Components**: source-controller, kustomize-controller, helm-controller, notification-controller
- **Kubernetes Compatibility**: Supports Kubernetes 1.20+
- **Kind Cluster**: `services-amer`

This setup provides a robust foundation for GitOps-based cluster management with automatic synchronization, monitoring, and security best practices. 