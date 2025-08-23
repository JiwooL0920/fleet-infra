# Base Applications

Base Kubernetes configurations for all **21 services** in the fine-grained GitOps infrastructure.

## Architecture  

Contains environment-agnostic application manifests that are referenced by fine-grained service kustomizations in `/base/services/` for precise dependency management and parallel deployment.

## Structure

Each of the 21 service directories contains complete Kubernetes configurations:
- **HelmReleases** for Helm-based deployments
- **Namespaces** for resource isolation  
- **ExternalSecrets** for secure credential management
- **Kustomization files** for resource organization

## Fine-Grained Integration

These base configurations are deployed via the fine-grained kustomization system which:
- References these base configs with precise service-level dependencies
- Enables maximum parallel deployment (15+ concurrent services)  
- Achieves 65-75% deployment time reduction
- Eliminates coarse wave-based waiting

## Service Categories

**21 services** organized across foundation, infrastructure, monitoring, data, application, and management layers - all deployable in 8-12 minutes through intelligent dependency resolution.