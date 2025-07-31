# CloudNative PostgreSQL

PostgreSQL cluster configuration using the CloudNative PostgreSQL operator.

## Purpose

Manages a high-availability PostgreSQL 16 cluster with 3 instances, automated backups, and pre-configured databases.

## Components

- `postgresql-cluster.yaml` - Main PostgreSQL cluster configuration
- `databases/` - Pre-configured database definitions (appdb, temporal, temporal_visibility)