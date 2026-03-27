# OpenTelemetry Collector - Observability Pipeline

Central telemetry collection and routing for traces, metrics, and logs using OpenTelemetry.

## Purpose

- Unified telemetry collection endpoint for all applications
- OTLP receiver for modern OpenTelemetry SDK instrumentation
- Legacy protocol support (Jaeger, Zipkin) for backwards compatibility
- Intelligent routing to appropriate backends (Jaeger, Prometheus, Loki)
- Kubernetes metadata enrichment for all telemetry data

## Dependencies

- **Depends on**: jaeger (trace storage), loki (log storage), kube-prometheus-stack (metrics scraping)
- **Depended on by**: Application services that emit telemetry

## Endpoints

Applications can send telemetry to the collector using:

| Protocol | Port | Use Case |
|----------|------|----------|
| OTLP gRPC | 4317 | Primary - OpenTelemetry SDKs |
| OTLP HTTP | 4318 | HTTP-based OTLP clients |
| Jaeger gRPC | 14250 | Legacy Jaeger clients |
| Jaeger Thrift | 14268 | Legacy Jaeger HTTP |
| Jaeger Compact | 6831 | Legacy Jaeger UDP |
| Zipkin | 9411 | Legacy Zipkin clients |

## Telemetry Flow

```
Applications ─┬─ OTLP ──────┐
              ├─ Jaeger ────┼──► OTEL Collector ─┬──► Jaeger (traces)
              └─ Zipkin ────┘                    ├──► Prometheus (metrics)
                                                 └──► Loki (logs)
```

## Configuration

The collector is configured with:
- **Receivers**: OTLP, Jaeger, Zipkin, Prometheus
- **Processors**: Batch, Memory Limiter, K8s Attributes
- **Exporters**: OTLP/Jaeger, Prometheus, Loki
