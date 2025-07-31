# Services Directory

Wave 4 application services with database dependencies.

## Purpose

Contains application services that require database connectivity and are deployed after infrastructure is established.

## Services

- `n8n.yaml` - Workflow automation engine (requires PostgreSQL)
- `temporal.yaml` - Workflow orchestration platform (requires PostgreSQL)

These services deploy sequentially after database workloads are ready (Wave 4c follows Wave 4b).