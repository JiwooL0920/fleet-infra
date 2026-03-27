# Tools and MCP Integration

**Previous**: [[02-Getting-Started]] | **Next**: [[04-Agent-Patterns]]

---

## Tool Catalog for Your Infrastructure

This page documents all available tools and MCP servers that work with your current stack.

---

## Built-in Prometheus Tools

**Source**: kagent-tool-server (deployed automatically with kagent)

**Configuration**: Automatically configured to use your Prometheus endpoint:
```yaml
# From HelmRelease values
toolServer:
  enabled: true
  prometheus:
    url: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
```

### Tool List

#### 1. GeneratePromQLTool
**Purpose**: Translate natural language to PromQL queries

**Example Usage**:
- User: "Show me pods with high CPU usage"
- Tool generates: `sum(rate(container_cpu_usage_seconds_total[5m])) by (pod) > 0.8`

**When to Use**: First step in any metrics query workflow

**Parameters**:
- `prompt` (string): Natural language description of desired metric

#### 2. QueryTool
**Purpose**: Execute instant Prometheus queries

**Example**:
```promql
up{job="kube-prometheus-stack-kube-state-metrics"}
```

**Returns**: Current value of metric

**Parameters**:
- `query` (string): PromQL query
- `time` (optional): Evaluation timestamp (default: now)

#### 3. QueryRangeTool
**Purpose**: Execute time-series queries over a range

**Example**:
```promql
rate(container_cpu_usage_seconds_total{namespace="kagent"}[5m])
```

**Returns**: Time series data points

**Parameters**:
- `query` (string): PromQL query
- `start` (timestamp): Range start time
- `end` (timestamp): Range end time
- `step` (duration): Query resolution (e.g., "15s")

**Use Cases**:
- "Show me CPU usage over the last hour"
- "Plot memory trends for the last 24 hours"

#### 4. AlertsTool
**Purpose**: Retrieve currently firing alerts

**Example Output**:
```json
{
  "alerts": [
    {
      "labels": {
        "alertname": "KubePodCrashLooping",
        "namespace": "prod",
        "pod": "nginx-abc"
      },
      "state": "firing",
      "value": "5",
      "annotations": {
        "description": "Pod prod/nginx-abc is crash looping"
      }
    }
  ]
}
```

**Use Cases**:
- "Are there any alerts firing right now?"
- "What's wrong with the cluster?"

#### 5. AlertmanagersTool
**Purpose**: Get information about Alertmanager instances

**Returns**: List of Alertmanager endpoints and their health status

#### 6. RulesTool
**Purpose**: List alerting and recording rules

**Returns**: Configured Prometheus rules with their state

**Use Cases**:
- "What alerts are configured?"
- "Show me recording rules for CPU metrics"

#### 7. SeriesQueryTool
**Purpose**: Find time series matching label selectors

**Example**:
```promql
{job="kube-state-metrics", namespace="monitoring"}
```

**Returns**: List of matching time series with full label sets

**Use Cases**:
- "What metrics are available for namespace X?"
- "Find all metrics with label 'app=redis'"

#### 8. TSDBStatusTool
**Purpose**: Get TSDB (time-series database) status

**Returns**: Stats on series, chunks, samples, storage usage

**Use Cases**:
- "How many time series are being stored?"
- "Is Prometheus running out of storage?"

#### 9. MetadataTool
**Purpose**: Get metadata for metrics (help text, type)

**Example**:
```
Metric: container_cpu_usage_seconds_total
Type: counter
Help: Cumulative cpu time consumed by the container in seconds
```

**Use Cases**:
- "What does this metric measure?"
- "Is this a counter or gauge?"

#### 10. BuildInfoTool
**Purpose**: Get Prometheus build information

**Returns**: Version, build date, Go version

#### 11. RuntimeInfoTool
**Purpose**: Get Prometheus runtime state

**Returns**: Start time, reload time, corruption status, TSDB status

#### 12. WALReplayTool
**Purpose**: Get Write-Ahead Log replay status

**Returns**: WAL replay progress (useful after Prometheus restart)

---

## Grafana MCP Server Tools

**Source**: mcp-grafana (separate deployment)

**Deployment**:
```yaml
# apps/base/grafana-mcp/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: grafana-mcp-server
  namespace: kagent
spec:
  interval: 10m
  chart:
    spec:
      chart: mcp-grafana
      version: 0.1.x
      sourceRef:
        kind: HelmRepository
        name: kagent
        namespace: flux-system
  values:
    grafana:
      url: http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local
      apiKeySecretRef: grafana-api-key
      apiKeySecretKey: key

    prometheus:
      url: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090

    loki:
      url: http://loki-gateway.loki.svc.cluster.local
```

**RemoteMCPServer CRD**:
```yaml
# apps/base/grafana-mcp/remotemcpserver.yaml
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: grafana-mcpserver
  namespace: kagent
spec:
  url: http://grafana-mcp-server.kagent.svc.cluster.local:8000/sse
```

### Dashboard Management Tools

#### search_dashboards
**Purpose**: Find dashboards by title or tag

**Parameters**:
- `query` (string): Search term
- `tag` (string, optional): Filter by tag

**Example**: "Find all Kubernetes dashboards"

#### get_dashboard
**Purpose**: Retrieve dashboard JSON by UID

**Returns**: Full dashboard definition

#### create_dashboard
**Purpose**: Create new dashboard from JSON

**Use Cases**:
- "Create a dashboard showing pod CPU and memory"
- Agent can generate dashboard JSON using tools

#### update_dashboard
**Purpose**: Update existing dashboard

#### delete_dashboard
**Purpose**: Delete dashboard by UID (should require HITL approval!)

#### get_dashboard_versions
**Purpose**: List version history of dashboard

---

### Loki (Logs) Tools

#### query_loki_logs
**Purpose**: Query Loki logs with LogQL

**Example**:
```logql
{namespace="kagent", app="observability-agent"} |= "error" | json
```

**Parameters**:
- `query` (string): LogQL query
- `start` (timestamp): Start time
- `end` (timestamp): End time
- `limit` (int): Max results

**Use Cases**:
- "Show me error logs from kagent namespace in the last hour"
- "Find logs containing 'OOMKilled'"

#### query_loki_stats
**Purpose**: Get log volume statistics

**Returns**: Count of log lines matching query over time

**Use Cases**:
- "How many errors occurred per hour today?"
- "What's the log ingestion rate?"

#### list_loki_label_names
**Purpose**: List available Loki labels

**Returns**: Labels like `namespace`, `app`, `pod`, `container`

**Use Cases**:
- "What labels can I filter logs by?"

#### list_loki_label_values
**Purpose**: List values for a specific label

**Example**: For label `namespace`, returns: `["kagent", "monitoring", "flux-system", ...]`

---

### Prometheus Query Tools (via Grafana MCP)

#### query_prometheus
**Purpose**: Execute PromQL queries

**Similar to built-in QueryTool, but via Grafana MCP server**

#### list_prometheus_metric_names
**Purpose**: List all available Prometheus metric names

**Returns**: Array of metric names

**Use Cases**:
- "What metrics are available?"
- "Find metrics related to pods"

#### list_prometheus_label_values
**Purpose**: List values for a Prometheus label

**Example**: For label `job`, returns: `["kube-state-metrics", "node-exporter", ...]`

---

### Incident Management Tools

#### list_incidents
**Purpose**: Get Grafana Incident incidents

**Requires**: Grafana Incident plugin installed

**Returns**: Open incidents with details

#### create_incident
**Purpose**: Create new incident

**Parameters**:
- `title` (string): Incident title
- `severity` (string): Critical, High, Medium, Low

**Use Cases**:
- Agent detects anomaly and creates incident automatically
- "Create incident for pods crashing in production"

#### get_incident
**Purpose**: Get details of specific incident

#### add_activity_to_incident
**Purpose**: Add note/activity to incident

**Use Cases**:
- Agent documents investigation steps automatically
- "Update incident with RCA findings"

---

### OnCall Tools

#### list_oncall_users
**Purpose**: Get list of oncall users

**Requires**: Grafana OnCall plugin

#### list_oncall_teams
**Purpose**: List oncall teams

#### list_oncall_schedules
**Purpose**: Get oncall schedules

#### get_current_oncall_users
**Purpose**: Who is currently oncall?

**Use Cases**:
- "Who should I page for this issue?"
- "Is anyone on call right now?"

---

### Team Management Tools

#### list_teams
**Purpose**: Get Grafana teams

#### list_sift_investigations
**Purpose**: List Sift investigation sessions

---

## Kubernetes Tools (Built-in)

**Source**: kagent-tool-server

### k8s_get_resources
**Purpose**: List Kubernetes resources

**Parameters**:
- `resource_type` (string): e.g., "pods", "deployments", "services"
- `namespace` (string, optional): Filter by namespace
- `label_selector` (string, optional): Label filter

**Example**:
```
resource_type: pods
namespace: kagent
label_selector: app=observability-agent
```

**Returns**: List of resources with key fields (name, namespace, status)

### k8s_describe_resource
**Purpose**: Get detailed information about a resource

**Parameters**:
- `resource_type` (string): e.g., "pod"
- `name` (string): Resource name
- `namespace` (string): Namespace

**Returns**: Full resource YAML with status, events, conditions

### k8s_delete_resource
**Purpose**: Delete Kubernetes resource

**⚠️ DANGEROUS**: Should always have `requireApproval: true`

**Parameters**:
- `resource_type` (string)
- `name` (string)
- `namespace` (string)

### k8s_apply_manifest
**Purpose**: Apply YAML manifest to cluster

**⚠️ DANGEROUS**: Should always have `requireApproval: true`

**Parameters**:
- `manifest` (string): YAML content

**Use Cases**:
- "Create a new deployment with these specs"
- "Update ConfigMap with new values"

### k8s_get_available_api_resources
**Purpose**: List all available API resource types

**Returns**: Resource types like "pods", "deployments", "helmreleases.helm.toolkit.fluxcd.io"

**Use Cases**:
- "What custom resources are available?"
- "Can I query Flux CD resources?"

---

## Jaeger / OpenTelemetry Tools

**Status**: Not yet available in kagent MCP catalog (as of v0.2.32)

**Workaround**: Create custom MCP server for Jaeger

### Custom Jaeger MCP Server (Example)

**Capabilities**:
- Query traces by service, operation, tags
- Get trace details by trace ID
- Find slow traces (duration > threshold)
- List services and operations

**Implementation**: Python MCP server using `jaeger-client` library

**Deployment**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: MCPServer
metadata:
  name: jaeger-mcp
  namespace: kagent
spec:
  image: your-registry.io/jaeger-mcp:v1.0
  command:
    - python
    - -m
    - jaeger_mcp
  env:
    - name: JAEGER_QUERY_URL
      value: http://jaeger-query.observability.svc.cluster.local:16686
```

**Sample Tool**: `query_traces`
```python
@mcp_tool
async def query_traces(
    service: str,
    operation: str = None,
    min_duration: str = None,
    limit: int = 20
):
    """Query Jaeger traces"""
    # Query Jaeger Query API
    # Return trace summaries
```

**Agent Integration**:
```yaml
spec:
  declarative:
    tools:
      - type: McpServer
        mcpServer:
          name: jaeger-mcp
          kind: MCPServer
          apiGroup: kagent.dev
          toolNames:
            - query_traces
            - get_trace_by_id
```

---

## Database Tools (Custom)

### PostgreSQL Tools (Your Cluster)

**Create Custom MCP Server**:

**Capabilities**:
- Execute SQL queries (read-only for safety)
- Explain query plans
- Get table schema
- Check slow queries from pg_stat_statements
- Analyze index usage

**Example Configuration**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: MCPServer
metadata:
  name: postgresql-mcp
  namespace: kagent
spec:
  image: your-registry.io/postgresql-mcp:v1.0
  command: ["/app/postgresql_mcp"]
  env:
    - name: POSTGRES_URL
      valueFrom:
        secretKeyRef:
          name: postgresql-cluster-app
          key: uri
```

**Safety**: Use dedicated read-only user:
```sql
CREATE USER kagent_readonly WITH PASSWORD 'xxx';
GRANT CONNECT ON DATABASE appdb TO kagent_readonly;
GRANT USAGE ON SCHEMA public TO kagent_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO kagent_readonly;
```

---

### Redis Tools (Your Cluster)

**Create Custom MCP Server**:

**Capabilities**:
- Get key information (type, TTL, size)
- Scan keys by pattern
- Get cache hit/miss rates from INFO stats
- Check memory usage
- Analyze slow commands

**Example Tool**: `redis_info`
```python
@mcp_tool
async def redis_info(section: str = "all"):
    """Get Redis INFO stats"""
    return await redis_client.info(section)
```

---

### ScyllaDB Tools (Your Cluster)

**ScyllaDB has DynamoDB-compatible API (Alternator)**

**Option 1**: Use AWS DynamoDB SDK with Alternator endpoint

**Option 2**: Create custom CQL MCP server

**Capabilities**:
- Query tables via CQL
- Get table schema
- Check compaction stats
- Analyze partition sizes
- Monitor read/write latencies

**Example Configuration**:
```yaml
env:
  - name: SCYLLA_HOSTS
    value: scylla-client.scylla.svc.cluster.local
  - name: SCYLLA_PORT
    value: "9042"
```

---

## N8N Tools (Your Workflow Engine)

**Create N8N MCP Server**:

**Capabilities**:
- List workflows
- Trigger workflow execution
- Get workflow execution status
- Retrieve execution logs

**Example Tool**: `trigger_n8n_workflow`
```python
@mcp_tool
async def trigger_n8n_workflow(workflow_id: str, data: dict):
    """Trigger N8N workflow with input data"""
    response = await n8n_client.post(
        f"/workflows/{workflow_id}/execute",
        json={"data": data}
    )
    return response.json()
```

**Agent Use Case**:
- "Trigger the incident-response workflow for this alert"
- "Execute the backup workflow for database X"

---

## Temporal Tools (Your Workflow Engine)

**Create Temporal MCP Server**:

**Capabilities**:
- List workflows by status
- Start workflow execution
- Signal running workflow
- Query workflow state
- Cancel workflow

**Example Tool**: `start_temporal_workflow`
```python
@mcp_tool
async def start_temporal_workflow(
    workflow_type: str,
    task_queue: str,
    input: dict
):
    """Start Temporal workflow"""
    handle = await temporal_client.start_workflow(
        workflow_type,
        input,
        id=f"agent-triggered-{uuid4()}",
        task_queue=task_queue
    )
    return {"workflow_id": handle.id}
```

**Agent Use Case**:
- "Start a data migration workflow"
- "Check status of long-running batch job"

---

## Flux CD Tools

**Available**: FluxCD maintains official agent-skills

**Repository**: https://github.com/fluxcd/agent-skills

**Installation**:
```bash
flux-operator skills install ghcr.io/fluxcd/agent-skills
```

**Skills**:
1. **gitops-knowledge**: Flux CD concepts and best practices
2. **gitops-repo-audit**: Analyze GitRepository resources
3. **gitops-cluster-debug**: Troubleshoot Kustomization and HelmRelease failures

**Integration with kagent**:
- Skills are container-based (run as separate pods)
- Agent invokes skill via HTTP API
- Skill performs Flux CD operations and returns results

**Example Agent Configuration**:
```yaml
spec:
  declarative:
    tools:
      - type: Skill
        skill:
          name: gitops-cluster-debug
          image: ghcr.io/fluxcd/agent-skills:latest
          command: ["/app/gitops-cluster-debug"]
```

---

## GitHub MCP Server

**Available**: In kagent contrib/tools/

**Deployment**:
```yaml
# apps/base/github-mcp/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: github-mcp-server
  namespace: kagent
spec:
  chart:
    spec:
      chart: github-mcp-server
      sourceRef:
        kind: HelmRepository
        name: kagent
  values:
    github:
      tokenSecretRef: github-token
      tokenSecretKey: token
```

**Capabilities**:
- List repositories, issues, PRs
- Create/update/close issues
- Comment on PRs
- Get file contents
- Search code

**Use Cases**:
- "Create GitHub issue for this recurring error"
- "Search codebase for function usage"
- "What PRs are open in this repo?"

---

## K8sGPT MCP Server

**Available**: In kagent contrib/tools/

**Purpose**: Integrate K8sGPT troubleshooting into kagent agents

**Capabilities**:
- Analyze Kubernetes resources for issues
- Get K8sGPT explanations for errors
- List available analyzers

**Example Tool**: `k8sgpt_analyze`
```yaml
tools:
  - type: McpServer
    mcpServer:
      name: k8sgpt-mcp-server
      toolNames:
        - k8sgpt_analyze
```

**Agent Use Case**:
- "Why is my pod failing?"
- Agent invokes K8sGPT to analyze pod
- K8sGPT returns: "OOMKilled - memory limit too low"
- Agent synthesizes response with remediation steps

---

## Tool Configuration Best Practices

### 1. Use `requireApproval` for Destructive Operations

```yaml
tools:
  - type: McpServer
    mcpServer:
      name: k8s-tools
      toolNames:
        - k8s_get_resources  # Safe, no approval
      requireApproval:
        - k8s_delete_resource  # Dangerous!
        - k8s_apply_manifest   # Dangerous!
```

### 2. Limit Tool Scope Per Agent

Don't give all tools to all agents. Principle of least privilege:

**Good**:
```yaml
# Read-only observability agent
tools:
  - QueryTool
  - query_loki_logs
  - k8s_get_resources
  - k8s_describe_resource
```

**Bad**:
```yaml
# Over-privileged agent
tools:
  - "*"  # Don't do this!
```

### 3. Use Separate ModelConfigs for Embeddings

```yaml
# Expensive model for reasoning
modelConfig: gpt4-default

# Cheap model for embeddings
memory:
  modelConfig: text-embedding-ada-002
```

### 4. Test Tools Individually First

Before adding tool to agent:
```bash
# Test Prometheus tool manually
kubectl exec -it -n kagent kagent-tool-server-xxx -- \
  curl -X POST http://localhost:8000/tools/QueryTool \
  -H "Content-Type: application/json" \
  -d '{"query": "up"}'
```

---

## Creating Custom MCP Servers

See the Python MCP SDK documentation: https://github.com/modelcontextprotocol/python-sdk

**Example Structure**:
```python
from mcp import Server, Tool
from mcp.server.stdio import stdio_server

app = Server("my-custom-mcp")

@app.tool()
async def my_tool(param: str) -> str:
    """Tool description for LLM"""
    # Tool implementation
    return result

if __name__ == "__main__":
    stdio_server(app)
```

**Deploy as MCPServer**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: MCPServer
metadata:
  name: my-custom-mcp
spec:
  image: my-registry.io/my-mcp:v1.0
  command: ["python", "-m", "my_mcp"]
```

---

## What's Next?

- **[[04-Agent-Patterns]]** - Build agents using these tools
- **[[06-Your-Infrastructure]]** - Specific examples for your stack

---

**Previous**: [[02-Getting-Started]] | **Next**: [[04-Agent-Patterns]]
