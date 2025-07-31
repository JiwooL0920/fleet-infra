# Base Directory

Wave-based deployment configurations for the fleet infrastructure.

## Purpose

Orchestrates deployment order using a 5-wave system with dependency management to ensure proper service startup sequence and stability.

## Wave Structure

- **Wave 1**: Infrastructure Core (Traefik, LocalStack)
- **Wave 2**: Infrastructure Operators (CNPG, External Secrets)
- **Wave 3**: Infrastructure Configuration
- **Wave 4**: Mixed deployment - monitoring and databases in parallel, then services sequentially
- **Wave 5**: Database UI tools (depends on Wave 4 databases)

## Components

- Individual wave configuration files (`.yaml`)
- `infrastructure/` - Core infrastructure components by wave
- `database/` - Database workloads and UI tools
- `services/` - Application services
- `kustomization.yaml` - Main orchestration with resource ordering