# Flux System

Flux CD system configuration for the development cluster.

## Purpose

Contains Flux CD controllers and Git source configuration that manages GitOps synchronization for the development environment.

## Components

- `gotk-components.yaml` - Flux CD toolkit components and controllers
- `gotk-sync.yaml` - Git repository synchronization configuration
- `kustomization.yaml` - Flux system kustomization

Configured to track the `develop` branch with 1-minute sync intervals for development.