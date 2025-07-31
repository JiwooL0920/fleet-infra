# Database Directory

Database-related deployments organized by function.

## Purpose

Contains database workloads and their associated UI management tools with proper dependency ordering.

## Structure

- `workloads/` - Core database services (PostgreSQL cluster, Redis)
- `ui/` - Database administration tools (pgAdmin4, RedisInsight)

UI tools depend on their respective database workloads being available before deployment.