# Base Applications

Base Kustomization configurations for all applications in the fleet infrastructure.

## Purpose

Contains environment-agnostic application configurations that serve as the foundation for deployment across different environments (dev/prod).

## Structure

Each subdirectory represents a specific application or service with its complete Kubernetes configuration including:
- HelmReleases for Helm-based deployments
- Namespaces for resource isolation
- External secrets for secure credential management
- Kustomization files for resource organization