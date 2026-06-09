# ADR-009: Traefik as Ingress Controller

**Status:** Accepted
**Date:** 2025-01 (implemented), 2026-06 (documented as ADR)

## Context

The platform needs an ingress controller to route external traffic to 15+ services via `.local` domains. Requirements:

- CRD-based routing (GitOps-friendly, declarative)
- Middleware chaining (auth, rate limiting, headers)
- Dashboard for debugging routing
- Cross-namespace routing (services span many namespaces)
- Low resource footprint for local dev

## Decision

Use **Traefik** with IngressRoute CRDs and NodePort service type for Kind clusters.

Key configuration:
- `kubernetesCRD.allowCrossNamespace: true` — route to any namespace
- `kubernetesIngress.enabled: true` — also support standard Ingress resources
- `service.type: NodePort` — ports 30080/30443 for Kind
- Pod anti-affinity for HA in production (multi-replica)
- JSON access logs with security-sensitive headers redacted

## Options Considered

1. **Nginx Ingress Controller** — Industry standard, wide adoption. But: annotation-based config (not CRD-native), less composable middleware, no built-in dashboard, cross-namespace requires explicit grants.

2. **Traefik** (chosen) — IngressRoute CRDs are more expressive than annotations. Middleware is composable and reusable. Built-in dashboard. First-class cross-namespace support. Lower memory than Nginx for similar workloads.

3. **Envoy/Istio** — Extremely powerful L7 proxy. Massive overkill for local dev. Heavy sidecar injection model.

4. **Gateway API (native)** — Emerging standard. Not yet mature enough for full feature parity. Traefik supports it as a future migration path.

## Consequences

### Positive

- **IngressRoute CRDs**: Declarative, GitOps-native, more expressive than annotations
- **Middleware chaining**: Auth, rate limiting, headers as reusable middleware objects
- **Cross-namespace**: Single ingress controller routes to all 15+ services across namespaces
- **Dashboard**: Built-in UI for debugging routing (at `traefik.local`)
- **Low footprint**: ~50MB RAM per replica, suitable for Colima/Kind
- **Access logs**: JSON-formatted with sensitive header redaction (Authorization, Cookie)

### Negative

- IngressRoute is Traefik-specific (vendor lock-in vs standard Ingress/Gateway API)
- Smaller community than Nginx Ingress (fewer StackOverflow answers)
- Some enterprise features (rate limiting persistence) require Traefik Enterprise
- CRD API changes between major versions (v2 → v3 migration)

### Migration Path

Traefik supports Gateway API. When Gateway API matures, IngressRoutes can be incrementally migrated to HTTPRoute/Gateway resources without changing the controller.
