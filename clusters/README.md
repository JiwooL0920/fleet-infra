# Clusters Directory

Environment-specific cluster configurations for fine-grained GitOps deployment.

## Architecture

Contains environment-specific configurations that deploy the **16 active services** (21 total, 5 disabled) fine-grained GitOps system across different environments with complete isolation.

## Structure

- `stages/` - Environment-specific deployment configurations
  - `dev/` - Development environment (tracks develop branch)
  - Production configurations (tracks main branch)
  
Each environment deploys 16 active services using fine-grained service-level dependencies for 8-12 minute deployment times with maximum parallel execution.

## Environment Isolation

- **Complete separation** between development and production
- **Branch-based deployment**: dev tracks `develop`, prod tracks `main`
- **Service consistency**: Same fine-grained architecture across all environments
- **Performance parity**: Fine-grained dependencies deliver fast deployments in all environments
- **Flexible deployment**: Services can be enabled/disabled per environment