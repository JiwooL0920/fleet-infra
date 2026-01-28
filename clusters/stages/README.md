# Stages Directory

Environment stage configurations for fine-grained GitOps multi-environment deployment.

## Architecture

Organizes different deployment stages with **fine-grained service dependencies** across environments, delivering consistent 8-12 minute deployments regardless of environment.

## Structure

- `dev/` - Development environment (tracks `develop` branch)
  - Deploys 16 active services (21 total) with fine-grained dependencies
  - Fast parallel deployment for rapid development cycles
  - Cost-optimized resources (single replicas, reduced storage)
- `prod/` - Production environment (tracks `main` branch)  
  - Same service architecture with production configuration overrides
  - High availability (multiple replicas, extended retention)
  - Identical fine-grained dependency benefits in production

## Benefits

- **Environment Parity**: Same fine-grained architecture across dev/prod
- **Fast Feedback**: 8-12 minute deployments enable rapid iteration
- **Branch Isolation**: Complete separation via Git branch tracking
- **Performance Consistency**: Fine-grained benefits in all environments
- **Cost Optimization**: Dev uses minimal resources, prod scales appropriately