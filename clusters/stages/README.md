# Stages Directory

Environment stage configurations for multi-environment GitOps.

## Purpose

Organizes different deployment stages (development, production) with branch-specific tracking and environment isolation.

## Structure

- `dev/` - Development environment configuration (tracks `develop` branch)
- `prod/` - Production environment configuration (tracks `main` branch)

Each stage maintains complete separation and independent configuration management.