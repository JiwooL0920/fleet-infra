# Infrastructure Layer

This directory contains the **foundation services** that provide essential platform capabilities for the entire cluster. These services must be deployed first as they provide core functionality that other layers depend on.

## 🏗️ Purpose

The infrastructure layer provides:
- **Networking & Ingress** - External access to cluster services
- **Cloud Services Emulation** - Local development environment simulation  
- **Secrets Management** - Secure handling of sensitive configuration
- **Monitoring & Observability** - System health and performance tracking
- **GitOps Management** - Operational dashboards and tooling

## 📦 Services

### **Networking**
- **`traefik/`** - Ingress controller and load balancer
  - Provides external access to cluster services
  - Handles TLS termination and routing

### **Cloud Infrastructure**  
- **`localstack/`** - AWS services emulation
  - S3, Secrets Manager, DynamoDB, SQS, SNS, Lambda
  - Enables local development without AWS costs
- **`localstack-init/`** - LocalStack initialization scripts
  - Contains setup configurations for LocalStack services

### **Secrets Management**
- **`external-secrets-operator/`** - External Secrets Operator
  - Synchronizes secrets from external systems (LocalStack) to Kubernetes
  - Provides ClusterSecretStore configuration
- **`external-secrets-config/`** - External secrets configuration
  - Configures secret stores and secret synchronization policies

### **Monitoring**
- **`kube-prometheus-stack/`** - Complete monitoring solution
  - Prometheus (metrics collection)
  - Grafana (dashboards and visualization)
  - Alertmanager (alerting and notifications)
  - Node exporters (system metrics)

### **Management**
- **`weave-gitops/`** - GitOps dashboard
  - Web UI for Flux operations
  - Cluster state visualization and management

## 🔄 Deployment Order

Services in this layer are deployed in dependency order:
1. **Traefik** - Networking foundation
2. **LocalStack** - Cloud services emulation
3. **External Secrets Operator** - Secrets management foundation
4. **External Secrets Config** - Secret store configuration  
5. **Kube-Prometheus-Stack** - Monitoring infrastructure
6. **Weave GitOps** - Management dashboard

## 🔗 Dependencies

- **No external dependencies** - This is the foundation layer
- All services in `database/` and `apps/` depend on infrastructure services
- Provides shared services like ingress, monitoring, and secrets management

## 📝 Configuration

Environment-specific configurations are applied via patches in:
- `clusters/stages/dev/` - Development environment overrides
- `clusters/stages/prod/` - Production environment overrides

Base configurations are environment-agnostic and located in `infrastructure/base/`.