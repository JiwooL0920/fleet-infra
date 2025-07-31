# Infrastructure Core

Wave 1 foundational services deployed first.

## Purpose

Essential infrastructure services that must be available before any other components can function properly.

## Services

- `traefik.yaml` - Ingress controller for external traffic routing
- `localstack.yaml` - AWS services emulation for development

These services have the shortest timeout (5m) as they are critical for cluster functionality.