# VCR-Style Testing Fixtures for kagent

**Status**: Design Proposal
**Created**: 2026-04-04
**Target**: kagent multi-agent testing infrastructure

---

## Problem Statement

Testing kagent's multi-agent orchestration is challenging due to:

1. **Non-determinism**: LLM responses vary between runs, making behavioral assertions unreliable
2. **External Dependencies**: Tests require live Kubernetes clusters, Prometheus, GitHub, etc.
3. **Slow Feedback**: Real MCP tool calls to K8s API/Prometheus take seconds, multiplied across 8 agents
4. **Scenario Coverage**: Hard to reproduce edge cases (OOM pods, Flux reconciliation failures, network policy violations)
5. **CI Brittleness**: Flaky tests when external services are unavailable or rate-limited

**Goal**: Enable **deterministic, fast, reproducible** agent behavior verification without live infrastructure.

---

## Concept: VCR-Style Fixture Recording and Replay

Inspired by HTTP VCR libraries (Ruby VCR, Python vcrpy), we record MCP tool interactions during **real kagent sessions** and replay them during tests.

### Core Workflow

**Recording Phase** (run once per scenario):
1. Agent session executes against **real infrastructure** (dev cluster, live Prometheus, etc.)
2. **Intercept and capture** every MCP tool call: request (tool name, arguments) + response (result, errors)
3. Save as **fixture files** in `fixtures/scenarios/<scenario-name>/` directory
4. Annotate with agent routing metadata (which agent was invoked, why, A2A delegation tree)

**Replay Phase** (run in CI/local testing):
1. Mock MCP server loads fixture for requested scenario
2. Agent invokes tool (e.g., `k8s_get_pods`) with arguments
3. Mock server **matches request** to recorded fixture entry
4. Returns **recorded response** instead of calling real K8s API
5. Test asserts on agent's reasoning, tool sequence, final answer

### Key Benefits

- **Determinism**: Same fixture = same agent behavior every time
- **Speed**: No network calls, tests run in milliseconds instead of seconds
- **Isolation**: No K8s cluster, Prometheus, or GitHub required
- **Edge Cases**: Record rare failures (node pressure, API throttling) once, replay forever
- **CI Stability**: No flaky tests from external service downtime

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────┐
│  Test Runner (pytest/go test)                       │
│  ┌───────────────────────────────────────────────┐  │
│  │  Agent Under Test (coordinator/k8s/gitops)    │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  MCP Client (calls tools)               │  │  │
│  │  └──────────────┬──────────────────────────┘  │  │
│  └─────────────────┼─────────────────────────────┘  │
│                    │ stdio/HTTP                     │
│  ┌─────────────────▼─────────────────────────────┐  │
│  │  Mock MCP Server (Fixture Replay Mode)        │  │
│  │  - Loads fixtures/scenarios/<name>/           │  │
│  │  - Matches tool call → returns recorded resp  │  │
│  └────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘

Recording Mode (separate workflow):
┌─────────────────────────────────────────────────────┐
│  Live Agent Session (dev cluster)                   │
│  ┌───────────────────────────────────────────────┐  │
│  │  Agent (real execution)                       │  │
│  │  └─────────────┬─────────────────────────────┘  │
│  └────────────────┼────────────────────────────────┘
│                   │                                  │
│  ┌────────────────▼────────────────────────────────┐
│  │  Recording Proxy (transparent passthrough)      │
│  │  - Forwards to real MCP servers                 │
│  │  - Logs request/response pairs to disk          │
│  └────────────────┬────────────────────────────────┘
│                   │                                  │
│  ┌────────────────▼────────────────────────────────┐
│  │  Real MCP Servers (k8s, prometheus, github)     │
│  └─────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────┘
```

### Recording Mechanism Options

#### Option A: OTEL Trace Export (Recommended)
**Approach**: Instrument agent engine to export MCP tool calls as OpenTelemetry spans

**Pros**:
- Non-invasive: No changes to MCP protocol or agent logic
- Rich context: Captures agent reasoning, A2A delegation, LLM prompts/completions
- Production-ready: Can record from live systems, not just dev

**Cons**:
- Requires OTEL SDK integration in Python/Go ADK
- Fixture extraction needs post-processing from trace JSON

**Implementation**:
```python
# In agent engine, wrap MCP tool calls:
with tracer.start_as_current_span("mcp_tool_call") as span:
    span.set_attribute("tool.name", "k8s_get_pods")
    span.set_attribute("tool.args", json.dumps(args))
    result = mcp_client.call_tool("k8s_get_pods", args)
    span.set_attribute("tool.result", json.dumps(result))
```

Export to JSON, then script extracts tool call spans into fixture format.

#### Option B: MCP Proxy Layer
**Approach**: Standalone proxy between agent and MCP servers

**Pros**:
- Zero engine changes required
- Works with any MCP client implementation

**Cons**:
- Adds latency in recording mode
- Requires managing proxy lifecycle in tests

**Implementation**:
- Proxy listens on stdio/HTTP, forwards to real MCP servers
- Logs all traffic to `fixtures/scenarios/<name>/` as it flows through

#### Option C: Agent Engine Instrumentation
**Approach**: Add `--record-fixtures` flag to Python/Go ADK

**Pros**:
- Direct control over what gets recorded
- Can filter sensitive data (secrets, tokens) during recording

**Cons**:
- Engine code changes required
- Maintenance burden across Python and Go runtimes

**Recommendation**: Start with **Option A (OTEL)** for production-readiness and rich context.

---

## Fixture Format

### Directory Structure

```
fixtures/
└── scenarios/
    ├── pod-listing-success/
    │   ├── metadata.json                    # Scenario description
    │   ├── agent-config.yaml                # Agent CRD snapshot
    │   ├── model-config.yaml                # ModelConfig used
    │   ├── session.json                     # Initial query, expected final answer
    │   └── interactions/
    │       ├── 001-k8s_list_pods.json       # First tool call
    │       ├── 002-k8s_get_pod_logs.json    # Second tool call
    │       └── 003-prometheus_query.json    # Third tool call
    │
    ├── flux-reconciliation-failure/
    │   ├── metadata.json
    │   ├── agent-config.yaml
    │   ├── session.json
    │   └── interactions/
    │       ├── 001-k8s_list_kustomizations.json
    │       └── 002-k8s_get_events.json
    │
    └── gitops-pr-creation/
        ├── metadata.json
        ├── agent-config.yaml
        ├── session.json
        └── interactions/
            ├── 001-k8s_get_deployment.json
            ├── 002-github_create_branch.json
            ├── 003-github_commit_file.json
            └── 004-github_create_pr.json
```

### File Formats

#### `metadata.json`
```json
{
  "scenario": "pod-listing-success",
  "description": "coordinator-agent queries k8s-agent for pod status in default namespace",
  "recorded_at": "2026-04-04T10:30:00Z",
  "recorded_by": "human-operator",
  "agents_involved": ["coordinator-agent", "k8s-agent"],
  "mcp_servers": ["k8s-mcp", "prometheus-mcp"],
  "tags": ["basic", "read-only", "k8s"]
}
```

#### `session.json`
```json
{
  "initial_query": "Show me all pods in the default namespace",
  "expected_final_answer": {
    "contains": ["nginx-deployment", "Running", "1/1"],
    "not_contains": ["Error", "CrashLoopBackOff"]
  },
  "expected_agent_routing": {
    "coordinator": "delegates to k8s-agent",
    "k8s-agent": "calls k8s_list_pods tool"
  }
}
```

#### `interactions/001-k8s_list_pods.json`
```json
{
  "sequence": 1,
  "timestamp": "2026-04-04T10:30:05Z",
  "agent": "k8s-agent",
  "tool": "k8s_list_pods",
  "request": {
    "namespace": "default",
    "label_selector": null
  },
  "response": {
    "status": "success",
    "data": {
      "pods": [
        {
          "name": "nginx-deployment-7d64c8f5b9-abc12",
          "namespace": "default",
          "status": "Running",
          "ready": "1/1",
          "restarts": 0,
          "age": "2d"
        }
      ]
    }
  },
  "latency_ms": 45,
  "metadata": {
    "mcp_server": "k8s-mcp",
    "approval_required": false
  }
}
```

---

## Replay Mechanism

### Mock MCP Server Implementation

**Core Logic**:
1. **Load Fixture**: On startup, read `fixtures/scenarios/<name>/` into memory
2. **Index by Tool**: Build lookup table: `(tool_name, args_hash) → response`
3. **Match Requests**: When agent calls tool, hash arguments and lookup
4. **Return Recorded Response**: Send back recorded data
5. **Assert Sequence**: Optionally enforce exact order of tool calls

**Matching Strategies**:

#### Exact Match (Strict)
```python
def match(tool, args):
    key = (tool, json.dumps(args, sort_keys=True))
    return fixture_lookup[key]
```
**Use for**: Deterministic scenarios with no variance

#### Fuzzy Match (Flexible)
```python
def match(tool, args):
    # Match on tool name + subset of args (ignore timestamps, etc.)
    canonical = {k: v for k, v in args.items() if k not in ['_timestamp', '_request_id']}
    key = (tool, json.dumps(canonical, sort_keys=True))
    return fixture_lookup[key]
```
**Use for**: Scenarios where some args vary (query time ranges, pagination tokens)

### Integration with Test Framework

#### pytest Example (Python ADK)
```python
@pytest.fixture
def mock_mcp_server(scenario_name):
    """Start mock MCP server with fixture loaded"""
    server = MockMCPServer(fixture_path=f"fixtures/scenarios/{scenario_name}")
    server.start()
    yield server
    server.stop()

def test_pod_listing(mock_mcp_server):
    agent = Agent(name="k8s-agent", mcp_servers=[mock_mcp_server])
    response = agent.query("List pods in default namespace")

    # Assert tool sequence
    assert mock_mcp_server.calls == [
        ("k8s_list_pods", {"namespace": "default"})
    ]

    # Assert final answer
    assert "nginx-deployment" in response
    assert "Running" in response
```

#### go test Example (Go ADK)
```go
func TestPodListing(t *testing.T) {
    mockServer := NewMockMCPServer("fixtures/scenarios/pod-listing-success")
    defer mockServer.Close()

    agent := NewAgent("k8s-agent", WithMCPServers(mockServer))
    response, err := agent.Query("List pods in default namespace")
    require.NoError(t, err)

    // Assert tool calls
    assert.Equal(t, []ToolCall{
        {Name: "k8s_list_pods", Args: map[string]interface{}{"namespace": "default"}},
    }, mockServer.RecordedCalls())

    // Assert response
    assert.Contains(t, response, "nginx-deployment")
}
```

---

## Scenario Catalog

### Priority Scenarios to Record

#### 1. Basic Read Operations
- **pod-listing-success**: List pods in namespace
- **deployment-status**: Get deployment rollout status
- **node-resources**: Query node CPU/memory usage

#### 2. Flux GitOps
- **flux-sync-status**: Check kustomization sync state
- **flux-reconciliation-failure**: Handle reconciliation errors
- **helmrelease-pending**: Diagnose pending Helm releases

#### 3. Observability
- **prometheus-query-metrics**: Query Prometheus for pod CPU
- **loki-log-search**: Search logs via Loki
- **jaeger-trace-lookup**: Find distributed traces

#### 4. Security
- **kubescape-cve-scan**: Get CVE report from Kubescape CRDs
- **rbac-audit**: Check RBAC permissions for service account
- **network-policy-check**: Validate network policy enforcement

#### 5. FinOps
- **opencost-namespace-cost**: Get cost breakdown by namespace
- **resource-right-sizing**: Analyze over/under-provisioned pods

#### 6. GitOps Writes (Approval-Gated)
- **gitops-pr-creation**: Create draft PR for deployment change
- **gitops-pr-approval-denied**: Handle user rejecting tool approval
- **gitops-pr-approval-approved**: Handle user approving PR creation

#### 7. Multi-Agent Orchestration
- **coordinator-delegates-to-k8s**: coordinator → k8s-agent delegation
- **coordinator-parallel-agents**: coordinator spawns observability + security agents in parallel
- **agent-escalation**: k8s-agent escalates to security-agent for CVE scan

#### 8. Error Conditions
- **k8s-api-timeout**: Handle K8s API timeout errors
- **prometheus-query-syntax-error**: Handle invalid PromQL
- **github-rate-limit**: Handle GitHub API rate limiting
- **mcp-server-unavailable**: Handle MCP server connection failure

---

## CI Integration

### Test Pipeline

```yaml
# .github/workflows/agent-tests.yml
name: kagent Agent Tests

on: [pull_request]

jobs:
  test-agents:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pytest pytest-asyncio
          pip install -e ./python-adk

      - name: Run fixture-based agent tests
        run: |
          pytest tests/agents/ \
            --fixtures=fixtures/scenarios/ \
            --junit-xml=test-results.xml

      - name: Publish test results
        if: always()
        uses: mikepenz/action-junit-report@v4
        with:
          report_paths: 'test-results.xml'
```

### Fixture Validation

**Pre-commit Hook**: Validate fixture format before commit
```bash
#!/bin/bash
# .git/hooks/pre-commit
python scripts/validate-fixtures.py fixtures/scenarios/
```

**CI Check**: Ensure fixtures stay up-to-date with MCP tool schemas
```bash
# Compare fixture tool args with MCP server JSON schemas
python scripts/check-fixture-schema-drift.py
```

### Fixture Versioning

**Problem**: MCP tool schemas evolve (new args, renamed fields)

**Solution**: Version fixtures by MCP server version
```
fixtures/
└── scenarios/
    └── pod-listing-success/
        ├── v1/  # For k8s-mcp v1.0.0
        └── v2/  # For k8s-mcp v2.0.0 (added 'field_selector' arg)
```

Tests specify minimum MCP version:
```python
@pytest.mark.requires_mcp("k8s-mcp>=2.0.0")
def test_pod_filtering():
    ...
```

---

## Recording Workflow (Manual)

### Step-by-Step Process

**1. Identify Scenario**
```bash
# Create scenario directory
mkdir -p fixtures/scenarios/flux-reconciliation-failure
```

**2. Start Recording Session**
```bash
# Option A: OTEL export mode
export OTEL_EXPORTER=file
export OTEL_TRACES_FILE=fixtures/scenarios/flux-reconciliation-failure/traces.json
kagent-cli run coordinator-agent --trace-export

# Option B: Proxy mode
recording-proxy --output fixtures/scenarios/flux-reconciliation-failure/interactions/
kagent-cli run coordinator-agent --mcp-proxy localhost:8080
```

**3. Execute Scenario**
```
User: "Why is the traefik kustomization failing to reconcile?"
Agent: [performs tool calls, proxy/OTEL captures]
```

**4. Extract Fixture Files**
```bash
# If using OTEL
python scripts/otel-to-fixture.py \
  fixtures/scenarios/flux-reconciliation-failure/traces.json \
  --output fixtures/scenarios/flux-reconciliation-failure/

# If using proxy, files already written
```

**5. Annotate Metadata**
```bash
# Edit metadata.json, session.json manually
# Add expected_final_answer, agent_routing expectations
```

**6. Validate Fixture**
```bash
python scripts/validate-fixtures.py fixtures/scenarios/flux-reconciliation-failure/
```

**7. Test Replay**
```bash
pytest tests/agents/test_flux.py::test_reconciliation_failure
```

---

## Open Questions

### 1. LLM Response Non-Determinism
**Problem**: Even with identical tool responses, LLM may generate different reasoning

**Options**:
- **A**: Record LLM prompts/completions in fixtures (full determinism, but fixtures become LLM-version-specific)
- **B**: Assert only on tool call sequence + final answer keywords (tolerates reasoning variance)
- **C**: Use temperature=0 in tests + seed for reproducibility (requires LLM API support)

**Recommendation**: Start with **B** (keyword assertions), add **A** (LLM recordings) for critical scenarios

### 2. Fixture Maintenance Burden
**Problem**: 50+ scenarios × 5 tool calls each = 250+ fixture files to maintain

**Mitigation**:
- Automated fixture regeneration: `scripts/regenerate-fixtures.sh <scenario>`
- Schema drift detection in CI
- Fixture deduplication: Share common tool responses across scenarios

### 3. Approval-Gated Tools (HITL)
**Problem**: Tools requiring human approval (e.g., `github_create_pr`) need user interaction

**Options**:
- **A**: Pre-approve in fixture: `"approval_decision": "approved"` (bypass HITL in tests)
- **B**: Mock approval UI: Test harness auto-approves/denies based on scenario
- **C**: Record real approval decisions in fixture

**Recommendation**: **A** (pre-approve in fixture) for fast tests, **B** for testing approval flow logic

### 4. Time-Sensitive Data
**Problem**: Fixtures contain timestamps, TTLs, "5 minutes ago" strings

**Options**:
- **A**: Redact timestamps during recording: `"created_at": "<TIMESTAMP>"`
- **B**: Fuzzy matching: Ignore timestamp fields during replay matching
- **C**: Relative times: `"age_seconds": 300` instead of absolute timestamps

**Recommendation**: **B** (fuzzy matching) for simplicity, **C** for better test clarity

### 5. Multi-Agent Coordination
**Problem**: coordinator-agent spawns k8s-agent + observability-agent in parallel via A2A

**Fixture Structure**:
- Record interactions per agent separately?
- Or single fixture with interleaved tool calls from multiple agents?

**Recommendation**: Separate interaction directories per agent:
```
fixtures/scenarios/parallel-agents/
├── coordinator-agent/interactions/
├── k8s-agent/interactions/
└── observability-agent/interactions/
```

---

## Next Steps

### Phase 1: Proof of Concept
1. Implement mock MCP server (Python) with basic exact-match lookup
2. Manually create 3 fixtures: pod-listing, flux-status, prometheus-query
3. Write pytest tests using fixtures
4. Validate approach with kagent maintainers

### Phase 2: Recording Tooling
1. Add OTEL instrumentation to Python ADK for tool call tracing
2. Build `otel-to-fixture.py` script for extraction
3. Document recording workflow

### Phase 3: Scenario Library
1. Record 15+ priority scenarios (see Scenario Catalog)
2. Add CI pipeline for fixture-based tests
3. Set up fixture validation pre-commit hook

### Phase 4: Advanced Features
1. Implement fuzzy matching for time-sensitive data
2. Add fixture versioning by MCP server version
3. Build automated fixture regeneration tooling

---

## References

- **Ruby VCR**: https://github.com/vcr/vcr (HTTP recording inspiration)
- **Python vcrpy**: https://github.com/kevin1024/vcrpy (Python HTTP VCR)
- **Polly.JS**: https://netflix.github.io/pollyjs/ (JavaScript HTTP recording)
- **OpenTelemetry Tracing**: https://opentelemetry.io/docs/concepts/signals/traces/
- **MCP Protocol Spec**: https://spec.modelcontextprotocol.io/specification/
- **kagent Architecture**: `docs/kagent/01-Architecture.md`
- **kagent MCP Tools**: `docs/kagent/03-Tools-and-MCP.md`
