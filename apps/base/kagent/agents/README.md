# kagent Agent Platform — Architecture & Operational Metrics

## Agent Inventory

| Agent | Model | Role | Entry Point |
|---|---|---|---|
| `classifier-agent` | qwen2.5:3b | Input safety gate (ambiguous queries only) | Traefik fast-path fallback |
| `coordinator-agent` | qwen2.5:72b | Orchestrator — keyword-deterministic router | Direct (fast-path) or via classifier |
| `cluster-agent` | qwen2.5:14b | All k8s/flux/helm/obs for services-amer cluster (prefix-routed for multi-cluster) | A2A from coordinator |
| `observability-agent` | qwen2.5:14b | Fleet-wide Prometheus/Loki/alerts only | A2A from coordinator |
| `git-agent` | qwen2.5:72b | PR creation in fleet-infra | A2A from coordinator |
| `finops-agent` | qwen2.5:14b | OpenCost cost analysis + right-sizing | A2A from coordinator |

## Multi-Tier Request Flow

```
User query
  │
  ▼
Traefik (kagent.local)
  ├─ [Phase 1b-i] forwardAuth input-guardrail (regex, <5ms)
  │     ├─ Match → 400 + refusal envelope (never reaches kagent)
  │     └─ No match →
  │           ├─ [Fast-path] allow-list keywords only + no destructive verbs
  │           │     → coordinator-agent directly (0ms added)
  │           └─ [Classifier-path] ambiguous or destructive verbs present
  │                 → classifier-agent (qwen2.5:3b, ~2-3s)
  │                     ├─ allow → coordinator-agent
  │                     └─ refuse → refusal envelope
  ▼
coordinator-agent (qwen2.5:72b)
  ├─ Rule 1 FLEET  → observability-agent
├─ Rule 2 CLUSTER (default) → cluster-agent
  ├─ Rule 3 CHANGE → git-agent
  └─ Rule 4 COST   → finops-agent
        │
        ▼ (via agentgateway A2A — defense-in-depth AgentgatewayPolicy on A2A path)
     Worker agents → MCP tool servers
```

## Guardrails Summary

| Layer | Type | What it catches | Latency |
|---|---|---|---|
| Traefik input-guardrail (forwardAuth) | Deterministic regex | Literal injection strings, credential leaks | <5ms p99 |
| agentgateway A2A policy | Deterministic regex | Inter-agent injection, credential exfiltration | <1ms |
| classifier-agent | LLM (qwen2.5:3b) | Paraphrased injection, off-topic, offensive, destructive intent | ~2-3s p50 |
| coordinator backstop | Prompt rule | Anything that bypassed all prior layers | 0 added LLM calls |

## Termination Constants

```
MAX_RETRIES_PER_AGENT_PER_TURN       = 1    (agents do not retry themselves)
MAX_AGENT_DELEGATIONS_PER_TURN       = 8    (coordinator: covers classifier + fan-out)
MAX_TOOL_CALLS_PER_AGENT_INVOCATION  = 15   (per worker per turn)
WALL_CLOCK_BUDGET_PER_TURN           = 120s (escalate → structured ESCALATION_NEEDED envelope)
```

## Anti-Pattern Audit Status (Phase 5)

| Anti-pattern | Status | Detail |
|---|---|---|
| God Agent | Borderline — monitored | cluster-agent has 26 tools (18 k8s + 5 helm + 3 grafana). Alert fires at >32. ADR in `cluster-agent/base/agent.yaml`. |
| Excessive layering | Compliant | Coordinator depth=1 always. Prompt rule prevents coordinator calling coordinator. |
| No observability | Resolved | OTel → Jaeger, Prometheus PodMonitor, Loki structured labels, Grafana dashboard. |

## Context Window Budgets

| Agent | tokenThreshold | Notes |
|---|---|---|
| coordinator-agent | 12000 | Sees aggregated worker responses; compact aggressively |
| cluster-agent | 24000 | Handles large kubectl/log output; wider budget justified |
| observability-agent | 16000 | Fleet aggregations; medium |
| finops-agent | 16000 | Cost JSON can be large; medium |
| git-agent | 16000 | Multi-step PR workflow; medium |

## MCP Timeout Policy

| Server | Timeout | Rationale |
|---|---|---|
| k8s-tools-federated | 20s | k8s API fast; 30s was over-generous |
| helm-tools-federated | 20s | Helm list/get fast |
| opencost-mcp-server | 45s | Cost rollups can be slow |
| github-mcp-server | 45s | Network-dependent (external GitHub API) |

## Operational Metrics Baseline

> Populate after rollout complete (Phase 5 validation gate).

| Metric | Baseline (pre-rollout) | Target (post-rollout) |
|---|---|---|
| Throughput (queries/min) | TBD | TBD |
| p95 lead time — read queries | ~40s (cold) | <30s (with warmer) |
| p95 lead time — PR creation | ~120s | <120s |
| Cost (GPU-seconds per query) by class: read-only | TBD | TBD |
| Cost (GPU-seconds per query) by class: fan-out | TBD | TBD |
| Cost (GPU-seconds per query) by class: write/PR | TBD | TBD |
| Fast-path coverage % | N/A | >80% |
| Classifier false-positive rate % | N/A | <2% |

Fill in after first week of production traffic. If any metric regresses from baseline,
revisit pattern selection or agent design per the lecture's §16 rule.
