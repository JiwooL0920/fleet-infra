# Applications Layer

This directory contains the **business logic services** that provide end-user functionality. These applications depend on both infrastructure and database layers and are deployed last in the dependency chain.

## 🚀 Purpose

The applications layer provides:
- **Workflow Automation** - Business process automation and integration
- **Workflow Orchestration** - Distributed system coordination and reliability
- **End-User Services** - Production applications that deliver business value

## 📦 Services

### **Workflow Automation**
- **`n8n/`** - Workflow automation engine
  - Visual workflow builder and automation platform
  - Integrates with 200+ services and APIs
  - Database: Uses dedicated `n8n` PostgreSQL database
  - Features: Triggers, actions, data transformation, scheduling
  - Web interface available at `http://n8n.local` (via Traefik)

### **Workflow Orchestration**  
- **`temporal/`** - Distributed workflow orchestration platform
  - Microservice orchestration and durable execution
  - Database: Uses `temporal` and `temporal_visibility` PostgreSQL databases
  - Features: Workflow versioning, retry logic, monitoring, scaling
  - Components:
    - Frontend service (2 replicas)
    - History service (2 replicas) 
    - Matching service (2 replicas)
    - Worker service (2 replicas)
  - Web UI available at `http://localhost:8090` (via port-forward)

## 🔄 Deployment Order

Applications are deployed after all dependencies are ready:
1. **N8N** - Workflow automation platform
2. **Temporal** - Workflow orchestration engine

## 🔗 Dependencies

### **Requires (from infrastructure layer):**
- **Traefik** - Ingress routing for web interfaces
- **External Secrets** - Database credential management
- **Monitoring** - Application metrics and health checks

### **Requires (from database layer):**
- **PostgreSQL cluster** - Persistent data storage
  - N8N uses `n8n` database
  - Temporal uses `temporal` and `temporal_visibility` databases
- **Database credentials** - Auto-managed secrets for database access
- **CNPG operator** - Database lifecycle management

### **Provides:**
- **Business functionality** - End-user applications and services
- **Workflow capabilities** - Automation and orchestration features
- **Integration endpoints** - APIs and webhooks for external systems

## 🗃️ Database Integration

### **N8N Database Usage:**
- **Database**: `n8n` (PostgreSQL)
- **Connection**: Via `n8n-postgres-credentials` secret
- **Data**: Workflow definitions, execution history, user settings
- **Schema**: Automatically managed by N8N application

### **Temporal Database Usage:**
- **Primary Database**: `temporal` (PostgreSQL)
- **Visibility Database**: `temporal_visibility` (PostgreSQL)  
- **Connection**: Via `postgresql-cluster-app` secret
- **Data**: Workflow state, history, task queues, worker registrations
- **Schema**: Managed by Temporal schema tools

## 🌐 Access Points

### **Development Environment:**
- **N8N**: `http://n8n.local` (via Traefik ingress)
- **Temporal UI**: `http://localhost:8090` (via port-forward)

### **Production Environment:**
- URLs configured via environment-specific patches
- Proper DNS and TLS certificates applied

## 📊 Monitoring & Health

### **Health Checks:**
- **N8N**: HTTP health endpoint at `/healthz`
- **Temporal**: Built-in service health monitoring
- **Database Connectivity**: Automatic connection testing

### **Metrics:**
- Application metrics exported to Prometheus
- Database performance monitoring via CNPG
- Custom dashboards available in Grafana

## ⚙️ Resource Requirements

### **N8N:**
- CPU: 250m requests, 500m limits
- Memory: 256Mi requests, 512Mi limits
- Storage: EmptyDir (stateless, data in PostgreSQL)

### **Temporal:**
- Multiple services with individual resource limits
- Scales horizontally with 2 replicas per service
- Database-backed for durability and consistency

## 📝 Configuration

Environment-specific configurations are applied via patches in:
- `clusters/stages/dev/` - Development environment overrides
- `clusters/stages/prod/` - Production environment overrides

Base configurations are environment-agnostic and located in `apps/base/`.