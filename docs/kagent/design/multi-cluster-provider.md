# Multi-Cluster Provider Design

**Status**: Proposed
**Date**: 2026-04-04
**Authors**: System Architecture Team

---

## Problem Statement

The current kagent deployment operates in a **single-cluster model**: one coordinator-agent orchestrates 7 specialized agents (k8s-agent, gitops-agent, flux-agent, helm-agent, security-agent, observability-agent, finops-agent) within a single Kubernetes cluster. This architecture has limitations:

1. **No cross-cluster visibility**: Users managing multiple clusters (dev, staging, prod) must switch contexts manually or deploy separate kagent instances without coordination
2. **Fragmented operations**: Questions like "which cluster is running n8n version 1.50?" require querying multiple isolated kagent instances
3. **Inefficient gitops workflows**: Each cluster's gitops-agent operates independently, creating duplicate PRs for cross-cluster changes
4. **No unified session tracking**: User conversations cannot span multiple clusters without context loss

This design proposes a **multi-cluster provider pattern** where:
- One **meta-coordinator** routes queries to the appropriate cluster-specific kagent instance
- **Per-cluster agents** (k8s, flux, helm, security, observability, finops) operate on their respective clusters via distinct kubeconfig contexts
- **Shared gitops-agent** creates PRs that affect multiple clusters from a single Git repository (fleet-infra)
- **Session scoping** tracks which cluster(s) are relevant to a conversation

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                      Meta-Coordinator                        │
│  (72b model, runs in management cluster or host cluster)     │
│  - Parses user intent: which cluster(s) does this affect?   │
│  - Routes to cluster-specific agents via A2A protocol        │
│  - Aggregates responses from multiple clusters               │
└──────────────┬────────────────────────────┬──────────────────┘
               │                            │
       ┌───────▼─────────┐          ┌──────▼──────────┐
       │  Cluster A      │          │  Cluster B      │
       │  kagent         │          │  kagent         │
       │  ============   │          │  ============   │
       │  k8s-agent      │          │  k8s-agent      │
       │  flux-agent     │          │  flux-agent     │
       │  helm-agent     │          │  helm-agent     │
       │  security-agent │          │  security-agent │
       │  obs-agent      │          │  obs-agent      │
       │  finops-agent   │          │  finops-agent   │
       └─────────────────┘          └─────────────────┘
               │                            │
               └────────────┬───────────────┘
                            │
                    ┌───────▼────────┐
                    │  gitops-agent  │
                    │  (shared)      │
                    │  - GitHub MCP  │
                    │  - Creates PRs │
                    │  - Single repo │
                    └────────────────┘
```

### Component Mapping

| Component | Deployment Model | Rationale |
|-----------|------------------|-----------|
| **Meta-Coordinator** | 1x (management cluster) | Single routing brain, sees all clusters |
| **k8s-agent** | Per-cluster (N instances) | Direct access to cluster API, operates via kubeconfig context |
| **flux-agent** | Per-cluster (N instances) | Reads Flux CRDs from specific cluster, triggers reconciliation |
| **helm-agent** | Per-cluster (N instances) | Inspects HelmReleases in specific cluster namespace |
| **security-agent** | Per-cluster (N instances) | Reads Kubescape CRDs, RBAC policies per cluster |
| **observability-agent** | Per-cluster (N instances) | Queries cluster-specific Prometheus/Loki endpoints |
| **finops-agent** | Per-cluster (N instances) | Queries OpenCost MCP scoped to cluster costs |
| **gitops-agent** | 1x shared | Operates on Git repo (fleet-infra), not on cluster API |

---

## Routing Logic

### Query Classification

The meta-coordinator determines **cluster scope** using:

1. **Explicit cluster mentions**: "What pods are failing in prod?" → route to `prod-k8s-agent`
2. **Contextual inference**: "Is n8n healthy?" + session history shows recent prod queries → route to `prod-cluster`
3. **Multi-cluster queries**: "Compare Redis memory usage across dev and prod" → parallel queries to both clusters
4. **Git operations**: "Upgrade traefik to 3.0" → route to shared `gitops-agent` (creates PR affecting all clusters)

### Example Routing Scenarios

| User Query | Routing Decision | Agents Invoked |
|------------|------------------|----------------|
| "Show pods in dev" | Single cluster | dev-k8s-agent |
| "Is Flux synced in all clusters?" | Multi-cluster fan-out | dev-flux-agent, prod-flux-agent |
| "Increase n8n replicas to 3" | Shared gitops | gitops-agent (creates PR for all envs or specific env patch) |
| "What's costing the most in prod?" | Single cluster | prod-finops-agent |
| "Compare CVE counts dev vs prod" | Multi-cluster aggregation | dev-security-agent, prod-security-agent |

### A2A Tool Naming Convention

In the current single-cluster model, the coordinator's `a2aConfig` defines tools like:

```yaml
a2aConfig:
  skills:
    - id: infrastructure-query
      description: Delegate to k8s-agent, flux-agent, etc.
```

In multi-cluster, the `a2aConfig` would expand to:

```yaml
a2aConfig:
  skills:
    - id: infrastructure-query-dev
      description: Query dev cluster infrastructure
      tools:
        - k8s-agent-dev
        - flux-agent-dev
        - helm-agent-dev
    - id: infrastructure-query-prod
      description: Query prod cluster infrastructure
      tools:
        - k8s-agent-prod
        - flux-agent-prod
        - helm-agent-prod
    - id: infrastructure-change
      description: Create PR via shared gitops-agent
      tools:
        - gitops-agent  # singular, shared
```

**Key insight**: Each cluster's agents become distinct A2A tools. The meta-coordinator selects which tool(s) to invoke based on cluster scope.

---

## Shared vs Per-Cluster Agents

### Why gitops-agent is Shared

The `gitops-agent` operates on the **fleet-infra Git repository**, not on a Kubernetes cluster API. Key reasons for sharing:

1. **Single source of truth**: One Git repo manages all clusters' manifests
2. **Atomic cross-cluster changes**: A PR can update `clusters/stages/dev/` and `clusters/stages/prod/` simultaneously
3. **No cluster-specific context**: Creating a PR requires GitHub credentials, not kubeconfig
4. **Avoids duplicate PRs**: If dev-gitops-agent and prod-gitops-agent both tried to create PRs for "upgrade traefik", you'd get 2 conflicting PRs

**Implementation**: The shared gitops-agent runs in the management cluster (or a designated host cluster) with:
- GitHub token from ExternalSecrets (synced from LocalStack Secrets Manager)
- MCP server for GitHub API operations
- No kubeconfig — it never interacts with cluster APIs

### Why k8s/flux/helm agents are Per-Cluster

These agents **read from or write to cluster APIs**:

- **k8s-agent**: Executes `kubectl` commands scoped to a specific cluster's API endpoint
- **flux-agent**: Reads `Kustomization`, `HelmRelease` CRDs from a cluster's `flux-system` namespace
- **helm-agent**: Queries Helm release history via cluster API

**Implementation**: Each cluster's agents run with a **kubeconfig context** pointing to that cluster:

```yaml
# dev cluster agents
k8s-agent-dev:
  kubeconfig: /etc/kubeconfig/dev-context  # points to dev API server

# prod cluster agents
k8s-agent-prod:
  kubeconfig: /etc/kubeconfig/prod-context  # points to prod API server
```

**Access control**: Each cluster's ServiceAccount has RBAC permissions scoped to its own cluster. The dev-k8s-agent cannot accidentally modify prod resources.

---

## Session Scoping

### Problem: Context Continuity Across Clusters

In a multi-cluster environment, user questions may span multiple clusters within a single conversation:

1. "What pods are failing in dev?" → queries dev cluster
2. "What about prod?" → user expects prod cluster query without repeating "prod"
3. "Create a PR to fix both" → affects both clusters

Without session scoping, the meta-coordinator loses context and may route incorrectly.

### Proposed Solution: Cluster Context Tracking

The meta-coordinator maintains **session metadata** including:

```json
{
  "session_id": "sess_abc123",
  "active_clusters": ["dev", "prod"],
  "last_cluster": "prod",
  "query_history": [
    {"query": "What pods are failing in dev?", "cluster": "dev"},
    {"query": "What about prod?", "cluster": "prod"}
  ]
}
```

**Inference rules**:
- If query mentions cluster explicitly → override `last_cluster`
- If query says "same issue in X" → add X to `active_clusters`
- If query is ambiguous → use `last_cluster` as default
- If query says "both" or "all clusters" → query all in `active_clusters`

**Session persistence**: Store in ScyllaDB (chat history backend) with:
- Session ID as partition key
- Cluster context as session attributes
- TTL matching chat history retention policy

---

## Migration Path

### Phase 1: Single-Cluster (Current State)

**Status**: ✅ Implemented

- 8 agents in one cluster (coordinator + 7 specialists)
- No cross-cluster capability
- User must deploy separate kagent per cluster manually

### Phase 2: Multi-Cluster with Manual Routing

**Goal**: Prove multi-cluster routing works without breaking single-cluster deployments

**Changes**:
1. Deploy per-cluster kagent instances in dev and prod
2. Deploy meta-coordinator in management cluster
3. Update meta-coordinator's `a2aConfig` to include cluster-suffixed tools:
   ```yaml
   tools:
     - k8s-agent-dev
     - k8s-agent-prod
     - flux-agent-dev
     - flux-agent-prod
     # ... etc
     - gitops-agent  # shared, no suffix
   ```
4. Implement simple keyword-based routing ("dev", "prod", "staging") in meta-coordinator
5. Test with explicit cluster mentions: "Show pods in dev"

**Rollback safety**: Single-cluster deployments continue working unchanged. Users opt-in to multi-cluster by deploying meta-coordinator.

### Phase 3: Intelligent Routing + Session Scoping

**Goal**: Context-aware routing without explicit cluster mentions every query

**Changes**:
1. Add session metadata storage (ScyllaDB)
2. Implement cluster inference from:
   - Previous queries in session
   - Environment variables (e.g., CI/CD context)
   - Time-based patterns (e.g., "staging" during business hours)
3. Add ambiguity detection: "Your query could apply to dev or prod. Which cluster?"

**User experience**: "Is Flux synced?" → meta-coordinator asks "Which cluster?" → user says "prod" → future queries default to prod until context changes

### Phase 4: Unified Operations

**Goal**: Seamless multi-cluster operations with advanced features

**Enhancements**:
1. **Cross-cluster queries**: "Compare costs between dev and prod" → parallel fan-out, aggregated response
2. **Cluster drift detection**: "Are dev and prod configs in sync?" → diff Kustomization outputs
3. **Progressive rollouts**: "Deploy to dev, wait 1 hour, then deploy to prod if no alerts" → temporal workflow spanning clusters
4. **Unified dashboards**: Meta-coordinator exposes aggregated metrics from all clusters

**gitops-agent workflows**:
- Single PR with environment-specific patches:
  ```
  clusters/stages/dev/cluster-vars-patch.yaml   # dev-specific override
  clusters/stages/prod/cluster-vars-patch.yaml  # prod-specific override
  ```
- PR description auto-generated with:
  - Which clusters are affected
  - Diff preview per cluster
  - Rollout sequence (dev → staging → prod)

### Phase 5: Federation (Future)

**Goal**: Treat multiple clusters as a single logical unit

**Concepts**:
- Virtual cluster abstraction: "Deploy to all-us-east" → meta-coordinator fans out to 3 physical clusters
- Policy-driven routing: Security policies enforce "PII workloads → on-prem cluster only"
- Global resource view: "Show all Redis instances" → returns Redis from all clusters with labels

---

## Open Questions

### 1. Meta-Coordinator Placement

**Options**:
- **Option A**: Run in one of the managed clusters (e.g., dev cluster)
  - ✅ Simpler setup (no extra cluster)
  - ❌ Dev cluster downtime breaks meta-coordinator
- **Option B**: Run in separate management cluster
  - ✅ Isolated from managed cluster failures
  - ❌ Additional infrastructure cost
- **Option C**: Run outside Kubernetes (VM, cloud function)
  - ✅ Fully independent
  - ❌ Loses Kubernetes-native benefits (RBAC, secrets, observability)

**Recommendation**: Start with Option A for dev/testing, graduate to Option B for production.

### 2. Agent Instance Scaling

**Question**: Should each cluster have exactly 1 instance of each agent, or scale dynamically?

**Trade-offs**:
- **Fixed 1:1 mapping**: Predictable, simple routing, but may bottleneck on high query load
- **Dynamic scaling**: Auto-scale agents based on query volume, but routing becomes complex (which replica to send to?)

**Recommendation**: Start with 1:1, add load balancing later if query patterns show hotspots.

### 3. Failure Isolation

**Scenario**: Prod cluster is down. User asks "Is prod healthy?"

**Behavior options**:
- **Option A**: Meta-coordinator returns "Cannot reach prod cluster" and stops
- **Option B**: Meta-coordinator queries other clusters and says "Prod is down, but dev and staging are healthy"

**Recommendation**: Option B with graceful degradation. Unhealthy clusters shouldn't block queries about healthy clusters.

### 4. Cost Allocation for Multi-Cluster Queries

**Question**: How does finops-agent attribute cost of meta-coordinator?

**Challenges**:
- Meta-coordinator serves queries for all clusters
- Hard to split cost proportionally without query telemetry

**Recommendation**: Tag meta-coordinator as "shared infrastructure" in OpenCost, report separately from per-cluster costs.

### 5. RBAC for Cross-Cluster Operations

**Question**: Should meta-coordinator inherit permissions from all clusters, or have separate RBAC?

**Security concern**: If meta-coordinator has admin on all clusters, a compromised meta-coordinator = full breach.

**Recommendation**:
- Meta-coordinator has **read-only** access to cluster APIs (only for health checks)
- Actual write operations (kubectl apply, flux reconcile) delegated to per-cluster agents with cluster-scoped RBAC
- gitops-agent has **no** cluster API access, only GitHub write access (approval-gated)

---

## Success Metrics

1. **Deployment time**: Multi-cluster setup ≤ 2x single-cluster setup time
2. **Query latency**: <500ms overhead for cluster routing vs direct query
3. **Context accuracy**: ≥95% of ambiguous queries routed to correct cluster after 3 exchanges
4. **Failure isolation**: Downtime in 1 cluster does not block queries to other clusters
5. **Developer experience**: Users can ask "Show me prod" without specifying cluster name after first mention in session

---

## Related Documents

- `docs/kagent/01-Architecture.md` — Current single-cluster architecture
- `apps/base/kagent/coordinator-agent.yaml` — Coordinator CRD with A2A config
- `docs/kagent/design/a2a-protocol.md` — Agent-to-Agent communication protocol (if exists)
- `docs/kagent/design/session-management.md` — Session state and context tracking (if exists)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-04-04 | System Architecture Team | Initial proposal |
