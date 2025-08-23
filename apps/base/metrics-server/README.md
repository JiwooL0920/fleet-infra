# Metrics Server - Foundation Service

Kubernetes resource metrics collection service enabling cluster resource monitoring.

## Purpose

- Collects CPU and memory metrics from Kubernetes nodes and pods
- Provides metrics API for horizontal pod autoscaling (HPA)
- Foundation service for resource monitoring capabilities
- Enables resource-based scaling and monitoring

## Dependencies

- **Depends on**: None (foundation service)
- **Depended on by**: kube-prometheus-stack (consumes Kubernetes metrics for monitoring)