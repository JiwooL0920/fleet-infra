# ADR-011: KEDA for Event-Driven Autoscaling

**Status:** Accepted
**Date:** 2026 (implemented), 2026-06 (documented as ADR)

## Context

Standard Kubernetes HPA scales based on CPU/memory metrics. Our platform has workloads that need scaling based on external signals:

- Queue depth (Temporal task queues)
- Prometheus metrics (custom application metrics)
- Cron schedules (batch processing)
- External event sources (webhooks, message queues)

HPA alone cannot react to these signals without custom metrics adapters.

## Decision

Deploy **KEDA** (Kubernetes Event-Driven Autoscaling) v2.16.x alongside the existing metrics-server.

KEDA acts as a custom metrics API server and HPA controller, enabling `ScaledObject` resources that define scaling triggers from 60+ event sources.

```yaml
# Example: scale based on Prometheus metric
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
spec:
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_requests_per_second
        threshold: '100'
```

## Options Considered

1. **HPA + custom metrics adapter** — Write a custom adapter for each metric source. Pros: no new CRDs. Cons: significant development effort per source, maintenance burden, no community scalers.

2. **KEDA** (chosen) — Pre-built scalers for Prometheus, PostgreSQL, Redis, cron, HTTP, and 60+ more. CRD-based (`ScaledObject`), GitOps-friendly. CNCF Graduated project.

3. **Knative Serving** — Serverless autoscaling (scale to zero). Overkill for long-running services. Heavy dependency stack.

4. **Custom controllers** — Build bespoke scaling logic. Maximum flexibility. Maximum maintenance. Not justified for standard patterns.

## Consequences

### Positive

- **60+ scalers**: Pre-built integrations for Prometheus, PostgreSQL, Redis, cron, Kafka, SQS, etc.
- **Scale to zero**: KEDA can scale deployments to 0 replicas when idle (cost savings for dev)
- **GitOps-native**: `ScaledObject` CRDs declared alongside workloads
- **HPA-compatible**: KEDA creates and manages HPA objects under the hood
- **Lightweight**: Operator + metrics server, ~128Mi RAM total
- **CNCF Graduated**: Production-proven, active community

### Negative

- Another CRD set to manage (`ScaledObject`, `TriggerAuthentication`, `ScaledJob`)
- Polling-based scaling (configurable interval, not instant)
- Scale-to-zero has cold start latency (pod startup time)
- Metrics server conflicts possible if custom metrics adapter already exists

### Current Usage

KEDA is deployed as infrastructure for future workload scaling. Primary planned use cases:
- Temporal worker scaling based on task queue depth
- n8n workflow execution scaling based on pending executions
- Batch job scheduling via `ScaledJob` with cron triggers
