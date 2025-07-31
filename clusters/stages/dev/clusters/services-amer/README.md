# Services Americas Development Cluster

Development cluster configuration for Americas region services.

## Purpose

Specific development cluster deployment configuration with Flux system setup tracking the `develop` branch.

## Components

- `flux-system/` - Flux CD controllers and Git source configuration
- `cluster-vars-patch.yaml` - Cluster-specific variable overrides
- `kustomization.yaml` - Cluster deployment orchestration

This cluster automatically syncs with the `develop` branch every 1 minute for rapid development iteration.