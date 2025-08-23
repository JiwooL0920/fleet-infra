# N8N - Application Service

Visual workflow automation platform with PostgreSQL backend for workflow persistence.

## Purpose

- Visual workflow builder with drag-and-drop interface
- Integration platform connecting various services and APIs
- PostgreSQL database backend for workflow and execution data
- Secure credential management via External Secrets
- Web-based workflow design and monitoring interface

## Dependencies

- **Depends on**: postgresql-cluster (requires PostgreSQL database for persistence)
- **Parallel with**: temporal (both applications depend on PostgreSQL)