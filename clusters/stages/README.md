# Stages Directory

Environment stage configurations for fine-grained GitOps multi-environment deployment.

## Architecture

Organizes different deployment stages with **fine-grained service dependencies** across environments, delivering consistent 8-12 minute deployments regardless of environment.

## Structure

- `dev/` - Development environment (tracks `develop` branch)
  - Deploys all 21 services with fine-grained dependencies
  - Fast parallel deployment for rapid development cycles
- `prod/` - Production environment (tracks `main` branch)  
  - Same 21-service architecture with production configuration overrides
  - Identical fine-grained dependency benefits in production

## Benefits

- **Environment Parity**: Same fine-grained architecture across dev/prod
- **Fast Feedback**: 8-12 minute deployments enable rapid iteration
- **Branch Isolation**: Complete separation via Git branch tracking
- **Performance Consistency**: Fine-grained benefits in all environments