# Flux CD System Configuration - Production

This directory contains the Flux CD system configuration for the production services-amer cluster.

## Configuration Details

### Git Repository Source
- **Branch**: `main` (production branch)
- **Sync Interval**: 10 minutes (more conservative for production)
- **Repository**: ssh://git@github.com/JiwooL0920/fleet-infra

### Kustomization Controller
- **Path**: `./clusters/stages/prod/clusters/services-amer`
- **Prune**: Enabled (removes resources not in Git)
- **Reconciliation Interval**: 10 minutes

## Production Characteristics

**Conservative Sync Strategy:**
- Longer sync intervals for production stability
- Automatic pruning of unused resources
- Health checks before declaring success

**Security:**
- SSH key authentication for Git access
- NetworkPolicy restrictions for pod communication
- RBAC policies for minimal required permissions

## Flux Components

- **Source Controller**: Manages Git repository synchronization
- **Kustomize Controller**: Applies Kubernetes manifests with Kustomize
- **Helm Controller**: Manages Helm releases
- **Notification Controller**: Handles alerts and notifications

## Monitoring

Monitor Flux CD system health with:
```bash
# Check Flux system status
flux get sources git
flux get kustomizations

# Check controller pods
kubectl get pods -n flux-system

# View reconciliation logs
kubectl logs -n flux-system deployment/source-controller
kubectl logs -n flux-system deployment/kustomize-controller
```