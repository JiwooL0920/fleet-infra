# ADR-010: OpenTelemetry Collector as Unified Telemetry Pipeline

**Status:** Accepted
**Date:** 2026 (implemented), 2026-06 (documented as ADR)

## Context

The observability stack has three signal types:
- **Traces**: Jaeger for distributed tracing
- **Metrics**: Prometheus for time-series metrics
- **Logs**: Loki for log aggregation

Without a collector, each application must know about each backend directly (Jaeger endpoint for traces, Prometheus scrape config, Loki push endpoint). This creates tight coupling and makes backend migrations painful.

## Decision

Deploy **OpenTelemetry Collector** (contrib distribution) as a unified ingestion point for all telemetry signals.

Pipeline configuration:
```
Receivers:                    Exporters:
  OTLP (gRPC + HTTP)    →      Traces  → Jaeger (OTLP)
  Jaeger (legacy)        →      Metrics → Prometheus (scrape endpoint)
  Zipkin (legacy)        →      Logs    → Loki (OTLP HTTP)
  Prometheus (self)
```

Processors applied to all signals: `memory_limiter` → `k8sattributes` → `batch`

Applications send to one endpoint (`otel-collector:4317`) using OTLP. The collector routes, enriches with K8s metadata, and exports to appropriate backends.

## Options Considered

1. **Direct-to-backend** — Apps send traces to Jaeger directly, metrics scraped by Prometheus, logs shipped by Promtail. Pros: fewer moving parts. Cons: tight coupling, no unified metadata enrichment, backend migration requires changing every app.

2. **OTel Collector** (chosen) — Single ingestion point, vendor-neutral protocol (OTLP), automatic K8s metadata enrichment, backend-agnostic applications. Standard pipeline for adding/swapping backends.

3. **Grafana Agent/Alloy** — Grafana's unified agent. Good integration with Grafana stack. But: less vendor-neutral, smaller community, tighter Grafana ecosystem lock-in.

## Consequences

### Positive

- **Vendor-neutral**: Applications only speak OTLP — backend swaps don't require app changes
- **K8s metadata enrichment**: Automatic pod/namespace/deployment labels on all signals
- **Protocol translation**: Accepts Jaeger, Zipkin, Prometheus formats and normalizes to OTLP
- **Single endpoint**: Applications configure one destination (`otel-collector:4317`)
- **Batching + memory limits**: Protects backends from burst traffic
- **Future-proof**: Add new exporters (Datadog, New Relic) without touching applications

### Negative

- Additional hop in the telemetry path (minor latency increase)
- Another component to operate and monitor
- Configuration complexity (receivers × processors × exporters matrix)
- Resource overhead (~128-512Mi RAM depending on throughput)
- Contrib distribution is large (includes all receivers/exporters, many unused)

### Current Pipeline Details

| Signal | Receivers | Processors | Exporters |
|--------|-----------|------------|-----------|
| Traces | OTLP, Jaeger, Zipkin | memory_limiter, k8sattributes, batch | otlp/jaeger |
| Metrics | OTLP, Prometheus | memory_limiter, k8sattributes, batch | prometheus, debug |
| Logs | OTLP | memory_limiter, k8sattributes, batch | otlphttp/loki, debug |
