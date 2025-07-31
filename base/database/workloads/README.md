# Database Workloads

Core database services deployed in Wave 4.

## Purpose

Contains the primary database workloads that provide data persistence and caching for applications.

## Services

- `cloudnative-pg.yaml` - PostgreSQL cluster configuration
- `redis.yaml` - Redis in-memory data store configuration

Both services deploy in parallel during Wave 4 with extended timeouts to ensure proper startup.