# ADR-007: kagent Orchestrator-Worker Multi-Agent Architecture

**Status:** Accepted
**Date:** 2026 (implemented), 2026-06 (documented as ADR)

## Context

We need an AI agent platform that can:
- Manage Kubernetes clusters (inspect, troubleshoot)
- Query observability data (Prometheus, Loki, Grafana)
- Propose infrastructure changes via GitOps PRs
- Analyze costs and security posture
- Handle Flux CD operations

A single monolithic agent would need all tools loaded simultaneously, causing context window bloat, confused routing, and security concerns (one prompt injection could trigger cluster writes).

## Decision

Implement an **orchestrator-worker pattern** using kagent (CNCF Sandbox project):

- **coordinator-agent** (single entry point): Analyzes complexity, decomposes tasks, spawns subagents in parallel via A2A protocol. Uses larger model (qwen2.5:72b) for planning.
- **7 specialized subagents** (fast-model-config): Each has a narrow tool set and focused system prompt.

```
coordinator-agent (orchestrator)
├── k8s-agent         — Pod status, deployments, events (18 tools)
├── observability-agent — Prometheus, Loki, Grafana dashboards
├── gitops-agent      — Creates draft PRs via GitHub MCP (write-gated)
├── flux-agent        — Flux sync status, reconciliation
├── helm-agent        — Read-only Helm inspection
├── security-agent    — RBAC audit, Kubescape CVEs, network policies
└── finops-agent      — Cost analysis via OpenCost MCP
```

**GitOps enforcement**: No agent applies changes directly to the cluster. All mutations flow through:
```
gitops-agent → GitHub PR → human review → merge → Flux reconcile
```

## Options Considered

1. **Monolithic agent with all tools** — Simple to deploy. But: bloated context, confused tool selection, security nightmare (all tools accessible from one prompt), can't optimize model size per task complexity.

2. **Orchestrator-worker with A2A** (chosen) — Coordinator delegates to specialists. Each subagent has minimal tool surface area. Write tools are approval-gated. Different model configs for planning vs execution.

3. **Independent agents (no coordinator)** — Users route to the right agent manually. Poor UX for complex queries spanning multiple domains.

4. **LangGraph/CrewAI** — Framework-specific, not Kubernetes-native, no CRD-based lifecycle management.

## Consequences

### Positive

- **Least-privilege**: Each agent only has tools it needs (security-agent can't write to cluster)
- **Model optimization**: Coordinator uses larger model for planning; workers use fast model for execution
- **Parallel execution**: Coordinator can spawn multiple subagents simultaneously
- **GitOps-only writes**: All cluster mutations go through PRs — human always in the loop
- **Kubernetes-native**: Agent lifecycle managed via CRDs, standard K8s tooling applies
- **Approval gates**: Write tools on k8s-agent and gitops-agent require explicit human approval

### Negative

- More complex deployment (8 agents vs 1)
- A2A protocol overhead for inter-agent communication
- Coordinator model quality directly impacts task decomposition accuracy
- Cold start latency for Python engine agents (~15s per agent)
- Local LLM (Ollama) quality limits for complex reasoning tasks

### Security Model

- gitops-agent **never merges** — humans always merge PRs
- k8s-agent write tools are approval-gated (HITL)
- helm-agent is explicitly read-only (write tools excluded)
- GitHub PAT scoped to repo-level access only
