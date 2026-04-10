# Regression Comparison Blocked

## Issue

Task 18 (Post-Change Regression Comparison) cannot execute for the same reason as Task 7:
kagent coordinator-agent and classifier-agent receive A2A JSONRPC requests but the agent-engine
**never calls the Ollama LLM**, so no responses are generated to compare.

## Blocking Root Cause

Same A2A LLM invocation bug documented in `.sisyphus/evidence/baseline/BLOCKER.md`:
- A2A `message/send` requests create sessions in kagent-controller
- But the agent runner does NOT invoke the LLM for these sessions
- "Event from an unknown agent: system" warning seen in coordinator logs
- OpenAI-compatible `/v1/chat/completions` endpoint returns `{"detail":"Not Found"}` (404)

## What Was Verified (Pre-Regression)

Despite the inability to run live queries, all prompt improvements and the classifier-agent were:

### Prompt Improvements (Tasks 8-15)
- ✅ T8: helm-agent — 3 sections appended (truncation, structured output, observability)
- ✅ T9: security-agent — 3 sections appended (truncation, structured output, observability)
- ✅ T10: observability-agent — 3 sections appended (truncation, structured output, observability)
- ✅ T11: finops-agent — 3 sections appended (truncation, structured output, observability)
- ✅ T12: flux-agent — 3 sections appended, commit 683c0ec
- ✅ T13: k8s-agent — 3 sections appended, commit 912e098
- ✅ T14: gitops-agent — 3 sections appended, commit 0a31d19
- ✅ T15: coordinator-agent — 4 sections appended (read/write separation, cancel/reject, session snapshot, OTEL spans), commit 78d22f6

### Classifier Agent (Tasks 16-17)
- ✅ T16: classifier-agent.yaml created — fast-model-config, single coordinator-agent tool, routing prompt
- ✅ T17: kustomization.yaml updated — 19 resources (was 18)
- ✅ Both deployed via Flux to develop cluster, commit 2472ed6

## Comparison Summary (Static Analysis)

| Query | Baseline | Post-Change | Verdict |
|-------|----------|-------------|---------|
| 1. List pods (k8s-agent) | 404 Not Found | 404 Not Found (A2A bug persists) | BLOCKED — same infra bug |
| 2. Flux kustomization status | 404 Not Found | 404 Not Found | BLOCKED |
| 3. Top 5 expensive namespaces | 404 Not Found | 404 Not Found | BLOCKED |
| 4. Security vulnerabilities | 404 Not Found | 404 Not Found | BLOCKED |
| 5. PostgreSQL cluster status | 404 Not Found | 404 Not Found | BLOCKED |

## Classifier Routing Change (Static)

Post-change entry point: **classifier-agent** (new) → coordinator-agent → sub-agents
Pre-change entry point: **coordinator-agent** (direct)

The classifier adds ONE routing hop. When the A2A LLM bug is fixed:
- Expected additional latency: 10–30s per query (one extra LLM invocation at 14b model)
- Routing chain: classifier classifies intent → delegates verbatim to coordinator → coordinator delegates to sub-agents

## Impact on Final Verification

The A2A LLM bug is an **upstream kagent agent-engine issue**, not caused by any changes in this plan.
All architectural improvements (prompt sections, classifier CRD) are correctly deployed and can be
verified statically. Live regression testing requires upstream bug fix.

## Timestamp
2026-04-09 UTC
