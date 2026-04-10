# Regression Comparison Summary

## Status: BLOCKED (A2A LLM invocation bug)

See BLOCKED.md for root cause analysis.

## Before/After Comparison

| Query | Before (Baseline T7) | After (Post-Change T18) | Delta |
|-------|---------------------|------------------------|-------|
| List pods in kagent namespace | 404 Not Found (A2A bug) | 404 Not Found (A2A bug) | No change — upstream blocked |
| Flux kustomization status | 404 Not Found (A2A bug) | 404 Not Found (A2A bug) | No change — upstream blocked |
| Top 5 expensive namespaces | 404 Not Found (A2A bug) | 404 Not Found (A2A bug) | No change — upstream blocked |
| Security vulnerabilities | 404 Not Found (A2A bug) | 404 Not Found (A2A bug) | No change — upstream blocked |
| PostgreSQL cluster status | 404 Not Found (A2A bug) | 404 Not Found (A2A bug) | No change — upstream blocked |

## Classifier Routing Analysis

**Post-change architecture adds one routing hop:**
- Before: User → coordinator-agent (entry point)
- After:  User → classifier-agent → coordinator-agent → sub-agents

**classifier-agent characteristics:**
- Model: fast-model-config (qwen2.5:14b) — lightweight, minimal latency
- Action: Classify query intent, pass VERBATIM to coordinator
- Does NOT decompose compound queries

## Baseline comparison context

Baseline captured at T7 (2026-04-04): All 5 queries returned 404 from A2A endpoint.
Regression captured at T18 (2026-04-09): Same result — upstream bug unchanged.

Both baseline and regression are blocked by same root cause. The architectural changes
(prompt improvements, classifier) are deployed and correct per static analysis.
