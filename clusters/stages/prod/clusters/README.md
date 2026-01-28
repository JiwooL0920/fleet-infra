# Production Clusters

This directory contains configuration for production Kubernetes clusters.

## Clusters

### services-amer
Americas production cluster for application services and infrastructure.

**Configuration:**
- **Cluster Name**: services-amer-prod
- **Environment**: Production
- **Region**: Americas (US East)
- **Flux Sync**: Tracks `main` branch with 10-minute interval
- **Resource Profile**: Performance-optimized with high availability

**Services Deployed:**
- Core infrastructure (Traefik, PostgreSQL, Redis)  
- Application services (N8N, Temporal)
- Monitoring stack (Prometheus, Grafana, Loki)
- Database management tools (pgAdmin4, RedisInsight)
- GitOps management (Weave GitOps)

## Production Characteristics

- **High Availability**: Multiple replicas and redundancy
- **Performance Optimization**: Higher resource allocations
- **Enhanced Security**: Stricter policies and controls
- **Extended Retention**: Longer backup and log retention
- **Comprehensive Monitoring**: Production-grade observability