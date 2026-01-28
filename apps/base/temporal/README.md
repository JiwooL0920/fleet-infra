# Temporal - Application Service

Distributed workflow orchestration engine providing durable task execution and state management.

## Purpose

- Distributed workflow orchestration with durable execution guarantees
- Task scheduling and retry logic with exponential backoff
- PostgreSQL backend for workflow history and state persistence
- Temporal UI for workflow monitoring and debugging
- Support for long-running, stateful business processes

## Dependencies

- **Depends on**: postgresql-cluster (requires PostgreSQL for workflow history and state)
- **Parallel with**: n8n (both applications depend on PostgreSQL)
