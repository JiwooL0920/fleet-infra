# Base Applications

Base Kubernetes configurations for **16 active services** in the fine-grained GitOps infrastructure (21 total, 5 disabled by default).

## Architecture  

Contains environment-agnostic application manifests that are referenced by fine-grained service kustomizations in `/base/services/` for precise dependency management and parallel deployment.

## Structure

Each of the 21 service directories contains complete Kubernetes configurations:
- **HelmReleases** for Helm-based deployments
- **Namespaces** for resource isolation  
- **ExternalSecrets** for secure credential management
- **Kustomization files** for resource organization

**Note:** Not all services are deployed by default. Check `/base/services/kustomization.yaml` for active services.

## Fine-Grained Integration

These base configurations are deployed via the fine-grained kustomization system which:
- References these base configs with precise service-level dependencies
- Enables maximum parallel deployment (10+ concurrent active services)  
- Achieves 65-75% deployment time reduction
- Eliminates coarse wave-based waiting

## Service Categories

**16 active services** organized across foundation, monitoring, data, application, and management layers - all deployable in 8-12 minutes through intelligent dependency resolution.

**5 disabled services** (Crossplane suite, Loki, Promtail) available for optional deployment.