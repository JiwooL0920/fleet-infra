# OpenTelemetry Agent Loop Metrics Design

## Problem Statement

kagent Phase 1 (Task 1) enabled basic distributed tracing via `otel.tracing.enabled: true` in the Helm chart. This sends spans to the OpenTelemetry Collector, which routes them to Jaeger for visualization.

**What's missing:**
- **Agent-level performance metrics**: How long does each agent take to process requests?
- **Token cost visibility**: How many input/output tokens does each agent consume per request?
- **Tool execution metrics**: Which tools are called most frequently? What's their success/failure rate?
- **Routing decision latency**: How long does the coordinator-agent take to analyze intent and dispatch?
- **End-to-end session metrics**: Total duration from user query to final response
- **Error tracking**: Which agents fail most often and why?

Without structured metrics and custom spans, operators cannot:
1. Identify performance bottlenecks in the agent loop
2. Optimize token costs by analyzing agent efficiency
3. Monitor SLOs for agent response time
4. Debug routing decisions in multi-agent workflows
5. Capacity plan based on resource consumption per agent

This design doc defines **what metrics to capture**, **how to structure trace spans**, and **implementation options** for instrumenting the kagent multi-agent loop.

---

## Current Observability Stack

### Architecture Overview

```
kagent pods
  └─ OTLP gRPC (4317) ──┐
                        │
                        ▼
    OpenTelemetry Collector (opentelemetry namespace)
      Receivers: OTLP gRPC/HTTP, Jaeger, Zipkin, Prometheus
      Processors: k8sattributes, batch, memory_limiter
      Exporters:
        - otlp/jaeger → Jaeger (traces)
        - prometheus → Prometheus (metrics via :8889 endpoint)
        - otlphttp/loki → Loki (logs)
```

### Trace Flow
- **Source**: kagent coordinator/agents emit OTLP spans
- **Pipeline**: `traces: [otlp, jaeger, zipkin] → [memory_limiter, k8sattributes, batch] → [otlp/jaeger, debug]`
- **Storage**: Jaeger all-in-one instance receives traces from OTEL Collector via OTLP
- **Enrichment**: k8sattributes processor adds Kubernetes metadata (namespace, pod, deployment)

### Metrics Flow
- **Source**: Applications emit OTLP metrics OR expose Prometheus endpoints
- **Pipeline**: `metrics: [otlp, prometheus] → [memory_limiter, k8sattributes, batch] → [prometheus, debug]`
- **Storage**: OTEL Collector exposes Prometheus endpoint at `:8889`, scraped by kube-prometheus-stack
- **ServiceMonitor pattern**: Example exists at `apps/base/kube-prometheus-stack/servicemonitor-agentic-ai.yaml`

### What's Already Working (Phase 1 - Task 1)
- kagent basic tracing enabled: `otel.tracing.enabled: true`
- OTEL Collector receives kagent spans via OTLP gRPC (4317)
- Spans are enriched with Kubernetes metadata
- Traces visible in Jaeger UI at `http://jaeger.local`

### What's Missing (Phase 2 - This Design)
- **Custom span hierarchy** for agent loop phases (see next section)
- **Span attributes** for token counts, tool names, routing decisions
- **Derived metrics** from traces (duration, token cost, success rate)
- **Prometheus metrics** exported by kagent or OTEL Collector processor
- **Grafana dashboard** visualizing agent performance and costs

---

## Trace Span Hierarchy

Proposed span structure for a single user request through the kagent multi-agent system:

```
coordinator.session (root span)
  │
  ├─ intent_classify (coordinator-agent analyzes query complexity)
  │
  ├─ agent.dispatch.k8s-agent (coordinator delegates to k8s-agent)
  │   ├─ tool.call.k8s_get_pods
  │   ├─ tool.call.k8s_describe_pod
  │   └─ tool.call.k8s_get_events
  │
  ├─ agent.dispatch.observability-agent (coordinator delegates to observability-agent)
  │   ├─ tool.call.mcp_grafana_query
  │   └─ tool.call.mcp_grafana_get_dashboard
  │
  └─ agent.dispatch.gitops-agent (coordinator creates PR for GitOps change)
      ├─ tool.call.github_mcp_create_pr
      └─ tool.call.github_mcp_add_comment
```

### Span Naming Conventions

| Span Name Pattern | Purpose | Parent Span |
|-------------------|---------|-------------|
| `coordinator.session` | Root span for entire user request | None (root) |
| `intent_classify` | Coordinator analyzes query and plans delegation | `coordinator.session` |
| `agent.dispatch.{agent-name}` | Coordinator dispatches subtask to subagent | `coordinator.session` |
| `tool.call.{tool-name}` | Agent executes a tool (k8s, Prometheus, GitHub, etc.) | `agent.dispatch.{agent-name}` |

### Required Span Attributes

All spans should include standard OpenTelemetry semantic conventions plus kagent-specific attributes:

**coordinator.session:**
- `kagent.session.id` (string): Unique session identifier
- `kagent.user.query` (string, first 200 chars): Original user question
- `kagent.model` (string): LLM model used (e.g., `qwen2.5:72b`)
- `kagent.total_agents` (int): Number of agents dispatched
- `kagent.total_tools` (int): Total tool calls across all agents

**intent_classify:**
- `kagent.intent.complexity` (string): `simple | moderate | complex`
- `kagent.intent.delegates` (string[]): Planned subagents to invoke

**agent.dispatch.{agent-name}:**
- `kagent.agent.name` (string): Agent name (e.g., `k8s-agent`)
- `kagent.agent.subtask` (string, first 200 chars): Subtask prompt sent to agent
- `kagent.agent.tokens.input` (int): Input tokens consumed
- `kagent.agent.tokens.output` (int): Output tokens generated
- `kagent.agent.model` (string): Model used (may differ from coordinator)
- `kagent.agent.status` (string): `success | failure | timeout`
- `kagent.agent.error` (string, optional): Error message if failed

**tool.call.{tool-name}:**
- `kagent.tool.name` (string): Tool name (e.g., `k8s_get_pods`)
- `kagent.tool.namespace` (string, optional): Target Kubernetes namespace
- `kagent.tool.status` (string): `success | failure`
- `kagent.tool.error` (string, optional): Error message if failed

---

## Metrics Catalog

Proposed metrics to derive from traces or emit directly:

### Duration Metrics (Histograms)

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `kagent_session_duration_seconds` | Histogram | `model`, `num_agents`, `status` | Total time from user query to response |
| `kagent_intent_classify_duration_seconds` | Histogram | `model`, `complexity` | Time spent analyzing intent |
| `kagent_agent_dispatch_duration_seconds` | Histogram | `agent`, `model`, `status` | Per-agent execution time |
| `kagent_tool_call_duration_seconds` | Histogram | `agent`, `tool`, `status` | Per-tool execution latency |

**Buckets (example for duration histograms):**
- `[0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]` seconds

### Token Consumption Metrics (Counters)

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `kagent_tokens_input_total` | Counter | `agent`, `model` | Cumulative input tokens per agent |
| `kagent_tokens_output_total` | Counter | `agent`, `model` | Cumulative output tokens per agent |
| `kagent_tokens_total` | Counter | `agent`, `model`, `direction={input\|output}` | Total tokens (alternative unified metric) |

### Tool Call Metrics (Counters)

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `kagent_tool_calls_total` | Counter | `agent`, `tool`, `status={success\|failure}` | Total tool invocations |
| `kagent_tool_errors_total` | Counter | `agent`, `tool`, `error_type` | Tool failures by error category |

### Agent Status Metrics (Counters)

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `kagent_agent_dispatches_total` | Counter | `agent`, `status={success\|failure\|timeout}` | Total agent invocations |
| `kagent_sessions_total` | Counter | `status={success\|failure\|partial}` | Total user sessions |

### Routing Decision Metrics

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `kagent_routing_decisions_total` | Counter | `complexity={simple\|moderate\|complex}`, `num_agents` | Intent classification results |
| `kagent_routing_latency_seconds` | Histogram | `complexity` | Time to decide which agents to invoke |

---

## Implementation Options

Three approaches to instrument kagent with agent-loop metrics, listed by complexity and control:

### Option 1: Upstream kagent Source Code Changes (RECOMMENDED)

**Overview:**
- Add OpenTelemetry instrumentation directly to kagent Go source code
- Emit custom spans with rich attributes for coordinator, agents, tools
- Export Prometheus metrics endpoint (`/metrics`) from controller pods

**Pros:**
- Full control over span structure and attributes
- Native Go OTEL SDK support (efficient, low overhead)
- Can capture internal state (e.g., LLM token counts from API responses)
- Clean separation: traces for request flow, metrics for aggregation
- Reusable by kagent community

**Cons:**
- Requires upstream PR to kagent repository
- Longer development cycle (review, merge, release)
- Must align with kagent maintainers' observability vision

**Implementation Steps:**
1. Add OTEL SDK dependencies to `go.mod` (github.com/open-telemetry/opentelemetry-go)
2. Instrument `coordinator-agent` loop:
   - Create root span `coordinator.session` on request start
   - Add child span `intent_classify` around analysis logic
   - Create `agent.dispatch.{name}` spans for each subagent call
3. Instrument tool execution in agent runtime:
   - Wrap tool calls with `tool.call.{name}` spans
   - Capture tool status, duration, error messages
4. Export Prometheus metrics:
   - Use `prometheus.NewHistogram` for durations
   - Use `prometheus.NewCounter` for token counts, tool calls
   - Expose `/metrics` endpoint on controller service
5. Update Helm chart:
   - Add `otel.metrics.enabled` flag
   - Create ServiceMonitor for Prometheus scraping

**Estimated Effort:** 2-3 weeks (dev + review + release)

---

### Option 2: OTEL Collector Span Metrics Processor (FASTEST TO DEPLOY)

**Overview:**
- Use existing traces from kagent (Phase 1 already working)
- Add `spanmetrics` processor to OTEL Collector pipeline
- Automatically derive metrics from span attributes without code changes

**Pros:**
- Zero kagent code changes required
- Deploy immediately (only OTEL Collector config change)
- Leverages existing trace instrumentation
- Metrics automatically updated as traces evolve

**Cons:**
- Limited to attributes already in spans (may need Option 3 first)
- Cannot capture internal state not exposed in traces
- Metrics naming constrained by spanmetrics conventions
- No control over metric cardinality (high-cardinality labels = explosion)

**Implementation Steps:**
1. Add `spanmetrics` processor to OTEL Collector config:
   ```yaml
   processors:
     spanmetrics:
       metrics_exporter: prometheus
       dimensions:
         - name: kagent.agent.name
         - name: kagent.tool.name
         - name: kagent.agent.status
       histogram_buckets: [0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
   ```
2. Update traces pipeline to include spanmetrics:
   ```yaml
   service:
     pipelines:
       traces:
         receivers: [otlp, jaeger, zipkin]
         processors: [memory_limiter, k8sattributes, spanmetrics, batch]
         exporters: [otlp/jaeger, debug]
   ```
3. Verify metrics appear in Prometheus:
   - Query: `calls_total{service_name="kagent"}`
   - Query: `duration_bucket{service_name="kagent"}`

**Estimated Effort:** 1-2 days (config + testing)

**Limitation:** Requires kagent to already emit spans with rich attributes. If current spans lack `kagent.agent.tokens.*`, this won't work without Option 1 or 3 first.

---

### Option 3: System Prompt Engineering (EXPERIMENTAL)

**Overview:**
- Modify coordinator/agent system prompts to instruct LLM to emit structured logs
- Parse logs in OTEL Collector or Fluent Bit to generate metrics
- No code changes to kagent, only prompt configuration

**Example Prompt Additions:**
```
When executing a tool, log a JSON line:
{"event":"tool.call", "tool":"k8s_get_pods", "status":"success", "duration_ms":245}

When dispatching to an agent, log:
{"event":"agent.dispatch", "agent":"k8s-agent", "tokens_in":120, "tokens_out":450}
```

**Pros:**
- Zero code changes (prompt-only approach)
- Fast to test with different formats
- Can iterate without redeploying kagent

**Cons:**
- Fragile: LLM may not reliably emit structured logs
- Parsing complexity in log pipeline
- Accuracy depends on LLM following instructions
- Not suitable for high-precision SLO monitoring
- May increase token costs (prompt overhead)

**Implementation Steps:**
1. Update agent CRs (`k8s-agent.yaml`, `coordinator-agent.yaml`) to add logging instructions
2. Configure OTEL Collector log receiver to parse JSON logs
3. Use `logstransform` processor to convert log events to metrics
4. Export to Prometheus

**Estimated Effort:** 1 week (prompt tuning + validation)

**Recommendation:** Use for prototyping only. Not production-ready.

---

## Dashboard Design

Proposed Grafana dashboard structure visualizing agent performance and costs.

### Dashboard: kagent Agent Loop Performance

**Row 1: Session Overview**
- **Panel 1.1 (Stat)**: Total Sessions (24h)
  - Metric: `increase(kagent_sessions_total[24h])`
  - Color: Green (success), Red (failure)
- **Panel 1.2 (Stat)**: Avg Session Duration
  - Metric: `histogram_quantile(0.5, kagent_session_duration_seconds_bucket)`
  - Unit: seconds
- **Panel 1.3 (Stat)**: P95 Session Duration
  - Metric: `histogram_quantile(0.95, kagent_session_duration_seconds_bucket)`
  - Unit: seconds

**Row 2: Agent Performance**
- **Panel 2.1 (Time Series)**: Agent Dispatch Duration by Agent
  - Metric: `histogram_quantile(0.95, sum by (agent) (rate(kagent_agent_dispatch_duration_seconds_bucket[5m])))`
  - Legend: `{{agent}}`
- **Panel 2.2 (Bar Chart)**: Agent Invocation Count (24h)
  - Metric: `sum by (agent) (increase(kagent_agent_dispatches_total[24h]))`
  - Order: Descending

**Row 3: Token Cost Analysis**
- **Panel 3.1 (Time Series)**: Input Tokens by Agent
  - Metric: `sum by (agent) (rate(kagent_tokens_input_total[5m]))`
  - Stack: True
- **Panel 3.2 (Time Series)**: Output Tokens by Agent
  - Metric: `sum by (agent) (rate(kagent_tokens_output_total[5m]))`
  - Stack: True
- **Panel 3.3 (Stat)**: Total Tokens (24h)
  - Metric: `sum(increase(kagent_tokens_total[24h]))`
  - Format: Number (with k/M suffix)

**Row 4: Tool Execution**
- **Panel 4.1 (Heatmap)**: Tool Call Latency Distribution
  - Metric: `sum by (tool, le) (rate(kagent_tool_call_duration_seconds_bucket[5m]))`
- **Panel 4.2 (Table)**: Top 10 Tools by Call Count
  - Metrics:
    - `sum by (tool) (increase(kagent_tool_calls_total[24h]))`
    - `sum by (tool) (increase(kagent_tool_calls_total{status="failure"}[24h]))`
  - Columns: Tool Name, Total Calls, Failures, Failure Rate

**Row 5: Error Tracking**
- **Panel 5.1 (Bar Gauge)**: Agent Failure Rate by Agent
  - Metric: `sum by (agent) (rate(kagent_agent_dispatches_total{status="failure"}[5m])) / sum by (agent) (rate(kagent_agent_dispatches_total[5m]))`
  - Thresholds: <5% green, 5-10% yellow, >10% red
- **Panel 5.2 (Logs Panel)**: Recent Agent Errors
  - Query: `{namespace="kagent"} |= "error" | json`
  - Fields: `agent`, `error`, `timestamp`

### ServiceMonitor Configuration

Reference pattern from `apps/base/kube-prometheus-stack/servicemonitor-agentic-ai.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kagent-controller
  namespace: monitoring
  labels:
    app: kagent
    release: monitoring-kube-prometheus-stack  # Required for discovery
spec:
  namespaceSelector:
    matchNames:
      - kagent
  selector:
    matchLabels:
      app.kubernetes.io/name: kagent-controller
  endpoints:
    - port: metrics  # Assumes controller service exposes :8080/metrics
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
```

**Deployment Steps:**
1. Add ServiceMonitor to `apps/base/kube-prometheus-stack/` after Option 1 or 2 is deployed
2. Verify Prometheus targets: `http://prometheus.local/targets` → Search "kagent"
3. Import dashboard JSON to Grafana

---

## Open Questions

### Technical Decisions
1. **Span attribute cardinality**: Should we include full `user.query` in spans, or hash/truncate?
   - Risk: High cardinality if users submit unique queries
   - Mitigation: First 200 chars + hash, store full query in logs
2. **Token tracking accuracy**: Rely on LLM API responses or parse agent logs?
   - Ollama API returns token counts in response headers
   - Need to verify kagent exposes this in agent runtime
3. **Metrics vs. Traces trade-off**: Should we emit both, or derive metrics from traces only?
   - Recommendation: Start with Option 2 (spanmetrics), add native metrics (Option 1) for cost-critical metrics later

### Operational Concerns
1. **Prometheus cardinality explosion**: If `kagent.tool.name` has 50+ unique values, metrics cardinality grows
   - Mitigation: Group low-frequency tools into `tool="other"`
2. **Trace sampling**: Should we sample traces in production to reduce Jaeger storage?
   - Current: No sampling (all traces stored)
   - Future: Tail-based sampling (keep only slow/failed traces)
3. **Dashboard access control**: Who can view agent token costs in Grafana?
   - Grafana in dev has no auth (open access)
   - Production needs RBAC for cost dashboards

### Future Enhancements
1. **Cost attribution**: Map token counts to USD cost per query
   - Requires: Cost per token for Ollama (free, but compute cost exists)
2. **Anomaly detection**: AlertManager rules for abnormal agent latency or token spikes
3. **Trace linking**: Connect kagent traces to underlying Kubernetes events (pod restarts, OOM kills)

---

## Next Steps

### Phase 2a: Quick Win (Week 1)
1. **Audit existing kagent traces**: Query Jaeger to see what spans/attributes already exist
   - URL: `http://jaeger.local` → Service: `kagent`
2. **Deploy Option 2 (spanmetrics)**: Add processor to OTEL Collector config
3. **Verify metrics in Prometheus**: Check for auto-generated duration/call metrics

### Phase 2b: Rich Instrumentation (Weeks 2-4)
1. **Implement Option 1**: Add OTEL SDK to kagent source code
2. **Define span hierarchy**: Coordinate with kagent maintainers on attribute naming
3. **Add token tracking**: Expose Ollama token counts in agent spans
4. **Create ServiceMonitor**: Enable Prometheus scraping of kagent metrics endpoint

### Phase 2c: Dashboard & Alerting (Week 5)
1. **Build Grafana dashboard**: Implement Row 1-5 design (see Dashboard Design section)
2. **Define SLOs**: e.g., P95 agent dispatch duration < 5s, failure rate < 2%
3. **Create AlertManager rules**: Alert on SLO violations

### Phase 3: Production Hardening
1. **Implement trace sampling**: Reduce Jaeger storage costs
2. **Add cost attribution**: Map tokens to compute cost
3. **Deploy to production**: Enable metrics in prod kagent Helm values

---

## References

- **OTEL Collector Config**: `apps/base/opentelemetry-collector/helmrelease.yaml`
- **ServiceMonitor Pattern**: `apps/base/kube-prometheus-stack/servicemonitor-agentic-ai.yaml`
- **kagent Helm Values**: `apps/base/kagent/helmrelease.yaml` (Phase 1: `otel.tracing.enabled: true`)
- **OpenTelemetry Semantic Conventions**: https://opentelemetry.io/docs/specs/semconv/
- **OTEL Collector Span Metrics Processor**: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/spanmetricsprocessor
- **kagent Documentation**: https://kagent.dev/docs/ (architecture, operations)

---

## Glossary

- **Span**: A single operation in a distributed trace (e.g., agent dispatch, tool call)
- **Trace**: Collection of spans representing an end-to-end request
- **ServiceMonitor**: Kubernetes CRD used by Prometheus Operator to auto-configure scraping
- **Span Metrics Processor**: OTEL Collector component that derives metrics from trace spans
- **Cardinality**: Number of unique label combinations in a metric (high cardinality = expensive)
- **P95**: 95th percentile latency (95% of requests complete faster than this value)
