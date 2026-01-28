# Production Environment Configuration

This directory contains production-specific configuration for the fleet-infra GitOps repository.

## Environment Characteristics

- **Environment**: Production
- **Git Branch**: Tracks `main` branch
- **Sync Interval**: 10 minutes (less frequent for stability)
- **Resource Allocation**: Performance-optimized with high availability
- **Monitoring**: Enhanced monitoring and alerting

## Directory Structure

```
prod/
├── base/                           # Base production configuration
│   ├── cluster-vars-patch.yaml    # Production cluster variables
│   └── kustomization.yaml         # Base production kustomization
└── clusters/
    └── services-amer/              # Americas production cluster
        ├── environment.env         # Production-specific configuration values
        ├── cluster-vars-patch.yaml # Cluster-specific overrides
        ├── flux-system/            # Flux CD configuration for production
        └── kustomization.yaml      # Main production kustomization

```

## Key Differences from Development

- **Higher resource limits**: CPU and memory allocated for production workloads
- **Multiple replicas**: High availability with multiple instances
- **Larger storage**: Increased storage allocations for production data
- **Extended retention**: Longer log and backup retention periods
- **Enhanced monitoring**: Production-grade monitoring and alerting
- **Stricter policies**: Enhanced security and compliance controls

## Configuration Management

Production environment uses environment-specific configuration overlays:

1. **Base defaults** from `base/services/environment.env`
2. **Production overrides** from `clusters/stages/prod/clusters/services-amer/environment.env`
3. **Cluster-specific patches** from `cluster-vars-patch.yaml` files

## Deployment Process

Production deployments follow the GitOps workflow:

1. Changes merged to `main` branch
2. Flux CD detects changes (10-minute sync interval)
3. Configuration validated and applied
4. Health checks and monitoring verify deployment success

## Safety Measures

- **Gradual rollout**: Changes deployed incrementally with health validation
- **Rollback procedures**: Automated rollback on deployment failures
- **Monitoring integration**: Real-time alerting on configuration or deployment issues
- **Change approval**: All production changes require approval process