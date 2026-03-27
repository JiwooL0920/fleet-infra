# Jaeger - Distributed Tracing Backend

Trace storage and visualization for distributed tracing using Jaeger.

## Purpose

- Distributed trace storage and querying
- Trace visualization and analysis via Jaeger UI
- OTLP receiver for OpenTelemetry Collector integration
- Service dependency graph visualization
- Root cause analysis for distributed systems

## Dependencies

- **Depends on**: traefik (ingress for Jaeger UI)
- **Depended on by**: opentelemetry-collector (exports traces to Jaeger)

## Access

- **Jaeger UI**: http://jaeger.local (via Traefik ingress)

## Architecture

```
OTEL Collector ──OTLP──► Jaeger All-in-One ◄── Jaeger UI
                              │
                              ▼
                        In-Memory Storage
```

## Configuration

Using all-in-one deployment mode with in-memory storage for development. For production, consider:
- Elasticsearch or Cassandra backend for persistence
- Separate collector/query/agent components for scalability
