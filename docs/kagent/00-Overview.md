# kagent Overview

## What is kagent?

**kagent** is a Kubernetes-native AI agent framework that enables you to build, deploy, and manage AI agents directly on Kubernetes infrastructure. It became a CNCF Sandbox project in May 2025 and provides a production-ready platform for agentic AI operations.

**Key Statistics**:
- GitHub Stars: 2,433
- CNCF Status: Sandbox (May 2025)
- Created: January 2025 by Solo.io
- Repository: https://github.com/kagent-dev/kagent
- Documentation: https://kagent.dev

## Why kagent Matters for Your Infrastructure

Your current stack (Flux CD, kube-prometheus-stack, Loki, Jaeger/OTel, PostgreSQL, Redis, ScyllaDB, Traefik, N8N, Temporal) is perfectly positioned to leverage kagent because:

1. **GitOps Native**: Flux CD integration for declarative agent deployment
2. **Observability Ready**: Built-in tools for Prometheus, Grafana, Loki
3. **Trace-Aware**: OpenTelemetry support for agent action tracing
4. **Database Support**: PostgreSQL for agent memory (pgvector), Redis for caching
5. **Workflow Integration**: Can orchestrate N8N workflows and Temporal processes
6. **Production-Grade**: Leverages existing monitoring, logging, and database infrastructure

## Core Concepts

### The Three Pillars

kagent is built on three foundational technologies:

1. **Model Context Protocol (MCP)**: Standardized way for LLMs to interact with external tools/systems
2. **Agent Development Kit (ADK)**: Python/Go SDK for building agent logic with streaming and HITL
3. **Agent-to-Agent Protocol (A2A)**: Enables agents to call other agents as tools with session continuity

### Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│                      kagent Platform                         │
├─────────────────────────────────────────────────────────────┤
│  Controller (Go)     │  Engine (Python/Go)  │  UI (Next.js) │
├─────────────────────────────────────────────────────────────┤
│             Kubernetes Custom Resources (CRDs)               │
│  • Agent (your AI agent definitions)                         │
│  • ModelConfig (LLM provider settings)                       │
│  • RemoteMCPServer / MCPServer (tool servers)                │
├─────────────────────────────────────────────────────────────┤
│                    MCP Tool Integrations                     │
│  Prometheus │ Grafana │ K8s │ Loki │ GitHub │ Custom...     │
├─────────────────────────────────────────────────────────────┤
│              Your Kubernetes Infrastructure                  │
│  Flux CD │ Prometheus │ Loki │ Jaeger │ PostgreSQL │ ...    │
└─────────────────────────────────────────────────────────────┘
```

### What Can You Build?

**With your infrastructure, kagent enables**:

- **Observability Agents**: Natural language queries to Prometheus/Loki ("Show me pods with high CPU in the last hour")
- **Incident Response**: Automated RCA using metrics, logs, traces, and K8s state
- **GitOps Operations**: Flux CD health checks, Kustomization troubleshooting, automated reconciliation
- **Database Ops**: PostgreSQL query optimization, Redis cache analysis, ScyllaDB performance monitoring
- **Workflow Automation**: Trigger N8N workflows or Temporal processes based on cluster events
- **Cost Optimization**: Analyze resource usage across namespaces and suggest rightsizing
- **Security Audits**: Scan for misconfigured ingresses (Traefik), certificate expiry, secret leaks

## Quick Example: Observability Agent

Here's what a simple agent looks like that can query your Prometheus and Loki:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: observability-agent
  namespace: kagent
spec:
  type: Declarative
  description: "Query Prometheus metrics and Loki logs using natural language"
  declarative:
    modelConfig: default-model-config
    systemMessage: |
      You are an observability expert for a Kubernetes cluster.
      Use Prometheus for metrics and Loki for logs.
      Always cite your sources with specific queries.
    tools:
      - type: McpServer
        mcpServer:
          name: kagent-tool-server  # Built-in Prometheus tools
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - GeneratePromQLTool
            - QueryTool
            - AlertsTool
      - type: McpServer
        mcpServer:
          name: grafana-mcpserver  # Loki queries
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - query_loki_logs
            - list_loki_label_names
```

**Usage**: "Show me all pods that restarted in the last 24 hours and their error logs"

**Agent Actions**:
1. Uses `GeneratePromQLTool` to create: `rate(kube_pod_container_status_restarts_total[24h]) > 0`
2. Executes query via `QueryTool`
3. For each pod, uses `query_loki_logs` with filters: `{namespace="...",pod="..."} |= "error"`
4. Returns synthesized report with metrics + log excerpts

## kagent vs Other Tools

| Feature | kagent | K8sGPT | HolmesGPT |
|---------|--------|--------|-----------|
| **Purpose** | General-purpose agent framework | K8s troubleshooting | End-to-end AIOps |
| **Scope** | Build any agent | Analyze K8s resources | Root cause analysis |
| **Extensibility** | MCP protocol (any tool) | Analyzers + integrations | Toolsets + runbooks |
| **Multi-Agent** | Yes (A2A protocol) | No | Limited |
| **CNCF Status** | Sandbox | Sandbox | Sandbox |
| **Integration** | Can use K8sGPT as MCP tool | Standalone | Can integrate |
| **Best For** | Custom agent workflows | Quick K8s diagnostics | Automated incident response |

**Your Use Case**: kagent is the platform to build custom agents that orchestrate K8sGPT (troubleshooting), HolmesGPT (RCA), and your own business logic.

## What's Next?

- **[[01-Architecture]]** - Deep dive into CRDs, A2A protocol, and agent lifecycle
- **[[02-Getting-Started]]** - Install kagent on your Flux CD cluster
- **[[03-Tools-and-MCP]]** - Catalog of tools for your infrastructure
- **[[04-Agent-Patterns]]** - Real agent CRD examples and best practices
- **[[05-Production-Use-Cases]]** - Production deployments and lessons learned
- **[[06-Your-Infrastructure]]** - Specific examples for your stack

## Quick Links

- [Official Documentation](https://kagent.dev)
- [GitHub Repository](https://github.com/kagent-dev/kagent)
- [Discord Community](https://bit.ly/kagentdiscord)
- [CNCF Slack #kagent](https://cloud-native.slack.com)
- [Flux CD Agent Skills](https://github.com/fluxcd/agent-skills)

---

**Next**: [[01-Architecture]] - Understanding the core components and how they work together.
