# kagent Architecture

**Previous**: [[00-Overview]] | **Next**: [[02-Getting-Started]]

---

## System Architecture

kagent consists of four main components running on Kubernetes:

### 1. Controller (Go)

**Purpose**: Kubernetes controller that watches CRDs and reconciles desired state

**Responsibilities**:
- Watch Agent, ModelConfig, MCPServer, RemoteMCPServer CRDs
- Translate CRDs into Deployments, Services, ConfigMaps
- Manage agent lifecycle (create, update, delete)
- Handle concurrency with sequential reconciliation model
- Implement garbage collection for deleted agents

**Key Files in Repository**:
- `go/core/internal/controller/` - Controller logic
- `go/core/internal/controller/translator/` - CRD to K8s resource translation
- `docs/architecture/controller-reconciliation.md` - Concurrency model

### 2. Engine (Python or Go ADK)

**Purpose**: Runtime that executes agent logic with LLM integration

**Two Runtime Options**:

#### Python ADK (Default)
- Startup: ~15 seconds
- Mature ecosystem with rich libraries
- Best for: Complex logic, rapid prototyping, Python MCP servers
- Image: `ghcr.io/kagent-dev/kagent-py-engine`

#### Go ADK (Experimental)
- Startup: ~2 seconds (faster cold starts)
- Lower memory footprint
- Best for: High-scale deployments, cost optimization
- Image: `ghcr.io/kagent-dev/kagent-go-engine`

**Responsibilities**:
- Execute agent loops (plan → tool call → observe → repeat)
- Stream responses via Server-Sent Events (SSE)
- Manage tool invocations with approval gates (HITL)
- Handle context compaction for long conversations
- Interface with vector memory (pgvector)

**Agent Specification in CRD**:
```yaml
spec:
  declarative:
    runtime: python  # or "go"
    stream: true     # Enable SSE streaming
```

### 3. UI (Next.js)

**Purpose**: Web interface for interacting with agents

**Features**:
- Chat interface with streaming responses
- Agent catalog and discovery
- Tool approval interface (HITL)
- Session history and management
- Model configuration UI

**Access**: Exposed via Service (ClusterIP by default, configurable to LoadBalancer/NodePort)

### 4. CLI

**Purpose**: Command-line tool for local development and testing

**Capabilities**:
- Run agents locally without Kubernetes
- Test MCP servers in development
- Debug agent configurations
- Generate CRD scaffolding

---

## Custom Resource Definitions (CRDs)

### Agent CRD

The primary resource that defines an AI agent.

**Full Structure**:
```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: my-agent
  namespace: kagent
spec:
  type: Declarative  # Currently only supported type
  description: "Human-readable description for A2A discovery"

  declarative:
    # Model Configuration
    modelConfig: default-model-config  # References ModelConfig CRD

    # System Prompt
    systemMessage: |
      You are a helpful assistant.
      Current date: 2026-03-25

    # Prompt Templates (Advanced)
    promptTemplate:
      configMapRef:
        name: my-prompt-template  # ConfigMap with Go text/template
        key: template.txt
      includes:  # Include other ConfigMaps
        - configMapRef:
            name: shared-instructions
            key: guidelines.txt

    # Runtime Selection
    runtime: python  # or "go"
    stream: true     # Enable streaming responses

    # Tools Configuration
    tools:
      # MCP Server Tools
      - type: McpServer
        mcpServer:
          name: kagent-tool-server
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - QueryTool
            - AlertsTool
          requireApproval:  # HITL gates
            - DeleteResourceTool

      # Other Agents as Tools (A2A)
      - type: Agent
        agent:
          name: promql-agent
          namespace: kagent

    # A2A Skills (for discovery by other agents)
    a2aConfig:
      skills:
        - id: prometheus-monitoring
          name: "Prometheus Query Expert"
          description: "Generate and execute PromQL queries"
          tags: ["prometheus", "metrics", "monitoring"]
          examples:
            - "Show me CPU usage for namespace X"
            - "What pods have high memory?"

    # Vector Memory Configuration
    memory:
      modelConfig: embedding-model-config  # For embeddings
      ttlDays: 30  # Retention period

    # Context Management
    context:
      compaction:
        compactionInterval: 5  # Compact every 5 messages
        modelConfig: compaction-model-config
```

**Key Concepts**:

1. **Tools**: Agents can use MCP servers, other agents, or built-in functions
2. **HITL (Human-in-the-Loop)**: `requireApproval` forces user confirmation for dangerous operations
3. **A2A Skills**: Make your agent discoverable to other agents with semantic descriptions
4. **Memory**: Vector-based conversation memory stored in PostgreSQL (pgvector extension required)
5. **Context Compaction**: Summarize old messages to stay within LLM context limits

### ModelConfig CRD

Defines LLM provider configuration with credentials.

**Basic Example** (OpenAI):
```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: gpt4-config
  namespace: kagent
spec:
  provider: OpenAI
  model: gpt-4o
  apiKeySecretRef: openai-api-key  # K8s Secret name
  apiKeySecretKey: key              # Key within Secret
  temperature: 0.7
  maxTokens: 4096
```

**Advanced Example** (Internal LiteLLM with TLS):
```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: litellm-internal
  namespace: kagent
spec:
  provider: OpenAI  # LiteLLM presents OpenAI-compatible API
  model: gpt-4
  apiKeySecretRef: litellm-api-key
  apiKeySecretKey: key

  openAI:
    baseUrl: https://litellm.internal.corp:8080  # Internal endpoint

  # TLS Configuration for internal CA
  tls:
    caCertSecretRef: litellm-ca-cert  # Secret with CA certificate
    caCertSecretKey: ca.crt
    disableSystemCAs: false           # Still use system CAs
    disableVerify: false              # Enforce verification
```

**Supported Providers**:
- OpenAI (including Azure OpenAI, LiteLLM proxies)
- Anthropic (Claude models)
- Google Vertex AI
- Ollama (local models)
- Bedrock (AWS)
- Custom OpenAI-compatible endpoints

**Your Infrastructure**: Use PostgreSQL-backed LiteLLM or expose Ollama via Service for cost optimization.

### RemoteMCPServer CRD

Defines an HTTP-based MCP server (SSE protocol).

**Example** (Grafana MCP):
```yaml
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: grafana-mcpserver
  namespace: kagent
spec:
  url: http://grafana-mcp-server.kagent.svc.cluster.local:8000/sse

  # Optional: Authentication
  headers:
    - name: Authorization
      valueFrom:
        secretKeyRef:
          name: grafana-mcp-creds
          key: token

  # Optional: Proxy Configuration
  proxy:
    url: http://proxy.corp.com:8080
    noProxy:
      - localhost
      - "*.svc.cluster.local"
```

### MCPServer CRD

Defines a stdio-based MCP server (runs as sidecar in agent pod).

**Example** (Custom Python MCP):
```yaml
apiVersion: kagent.dev/v1alpha2
kind: MCPServer
metadata:
  name: custom-python-mcp
  namespace: kagent
spec:
  image: my-registry.io/custom-mcp:v1.0
  command:
    - python
    - -m
    - mcp_server
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: db-creds
          key: url
```

**Use Case**: When you need MCP server to share agent pod resources or have access to pod-local files.

---

## Agent-to-Agent (A2A) Protocol

### Concept

Agents can invoke other agents as tools, enabling hierarchical problem decomposition.

**Example Flow**:
```
User: "Create a Grafana dashboard for pod CPU usage"
  ↓
ObservabilityAgent (parent)
  ├─ Invokes→ PromQLAgent: "Generate PromQL for pod CPU"
  │   └─ Returns: "sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)"
  └─ Uses→ GrafanaMCP: create_dashboard(query="...", title="...")
      └─ Returns: Dashboard URL
```

### A2A Skills

Skills are metadata that help agents discover each other's capabilities.

**Defining Skills** (in Agent CRD):
```yaml
spec:
  declarative:
    a2aConfig:
      skills:
        - id: flux-troubleshooting
          name: "Flux CD Expert"
          description: |
            Diagnose Flux CD reconciliation failures.
            Check HelmRelease, Kustomization, and GitRepository resources.
          tags: ["flux", "gitops", "troubleshooting"]
          examples:
            - "Why is my HelmRelease failing?"
            - "Check Flux system status"
            - "Show me Kustomization errors"

        - id: prometheus-querying
          name: "PromQL Query Builder"
          description: "Generate PromQL queries from natural language"
          tags: ["prometheus", "metrics", "promql"]
          examples:
            - "Show me pods with high memory"
            - "CPU usage by namespace"
```

**Using Another Agent** (in parent Agent):
```yaml
spec:
  declarative:
    tools:
      - type: Agent
        agent:
          name: flux-troubleshooter  # References another Agent CRD
          namespace: kagent
```

**A2A Communication**:
- Parent agent sends request to child agent via internal API
- Session continuity maintained (child has access to conversation history)
- Child agent's tool calls are visible in parent's trace
- Results are synthesized back to parent agent

### Session Management

**Key Features**:
- Each user conversation creates a session
- Sessions persist across multiple requests
- Memory is session-scoped (if enabled)
- Sessions can be resumed after agent restarts

---

## Human-in-the-Loop (HITL)

### Purpose

Prevent agents from executing dangerous operations without human approval.

### Implementation

**In Agent CRD**:
```yaml
spec:
  declarative:
    tools:
      - type: McpServer
        mcpServer:
          name: k8s-tools
          toolNames:
            - k8s_get_resources      # No approval needed
            - k8s_describe_resource  # No approval needed
          requireApproval:
            - k8s_delete_resource    # Requires approval
            - k8s_apply_manifest     # Requires approval
```

**Approval Flow**:
1. Agent decides to call `k8s_delete_resource`
2. Agent engine pauses and sends approval request to UI
3. User sees: "Agent wants to delete Pod 'nginx-xyz' in namespace 'prod'. Approve?"
4. User approves/denies
5. Agent receives response and continues or aborts

**ADK Integration** (Python):
```python
from kagent_adk import ToolContext

async def dangerous_operation(ctx: ToolContext):
    approved = await ctx.request_confirmation(
        message="About to delete 100 PVCs. This is irreversible.",
        details={"pvcs": pvc_list}
    )
    if not approved:
        return "Operation cancelled by user"
    # Proceed with deletion
```

**Your Use Cases**:
- Deleting Kubernetes resources
- Modifying Flux CD GitRepository sources
- Executing database migrations
- Scaling production workloads
- Applying security policies

---

## Data Flow: End-to-End Request

```
1. User sends message via UI/API
   ↓
2. Request hits kagent Engine (agent pod)
   ↓
3. Engine loads conversation history from PostgreSQL (if memory enabled)
   ↓
4. Engine constructs prompt with system message + history + tools
   ↓
5. LLM API call (via ModelConfig)
   ↓
6. LLM responds with tool call (e.g., "call QueryTool with 'up{job=\"kube-prometheus-stack\"}'")
   ↓
7. Engine invokes MCP Server (RemoteMCPServer or MCPServer)
   ↓
8. MCP Server executes tool (e.g., query Prometheus HTTP API)
   ↓
9. Tool result returned to Engine
   ↓
10. Engine appends result to conversation context
   ↓
11. Engine calls LLM again with updated context
   ↓
12. LLM synthesizes final response
   ↓
13. Response streamed to UI via SSE (if stream: true)
   ↓
14. Conversation saved to PostgreSQL memory (if enabled)
   ↓
15. OpenTelemetry trace exported to Jaeger (if observability enabled)
```

**Trace Example** (in Jaeger):
```
user_request [10s]
├─ load_memory [200ms]
├─ llm_call_1 [2s] - tool decision
├─ mcp_call: QueryTool [1.5s]
│  └─ prometheus_http_query [1.2s]
├─ llm_call_2 [3s] - synthesis
└─ save_memory [300ms]
```

---

## Prompt Template System

### Purpose

Reusable prompt components with dynamic substitution.

### Features

1. **Go text/template syntax**: `{{ .Variable }}`
2. **ConfigMap includes**: Compose prompts from multiple ConfigMaps
3. **Environment variables**: Inject cluster-specific values

### Example

**ConfigMap** (`shared-guidelines`):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: shared-guidelines
  namespace: kagent
data:
  guidelines.txt: |
    ## General Guidelines
    - Always cite sources with specific queries
    - Use metric names from Prometheus metadata
    - Check recent alerts before querying
```

**ConfigMap** (`observability-prompt`):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: observability-prompt
  namespace: kagent
data:
  template.txt: |
    You are an observability expert for a Kubernetes cluster.

    {{ template "guidelines.txt" }}

    ## Available Tools
    - Prometheus: metrics and alerts
    - Loki: log aggregation
    - Jaeger: distributed tracing

    Current cluster: {{ .CLUSTER_NAME }}
    Environment: {{ .ENVIRONMENT }}
```

**Agent CRD**:
```yaml
spec:
  declarative:
    promptTemplate:
      configMapRef:
        name: observability-prompt
        key: template.txt
      includes:
        - configMapRef:
            name: shared-guidelines
            key: guidelines.txt
```

**Substitution Variables** (from cluster-vars ConfigMap):
- Injected via `postBuild.substituteFrom` in Flux Kustomization
- Example: `CLUSTER_NAME`, `ENVIRONMENT`, `PROMETHEUS_URL`

---

## Memory System

### Architecture

kagent uses **PostgreSQL with pgvector** extension for vector-based memory.

**Components**:
1. **Embedding Model**: Converts text to vectors (via ModelConfig)
2. **Storage**: PostgreSQL table with vector column
3. **Retrieval**: Similarity search using pgvector operators

### Configuration

**Enable pgvector in PostgreSQL**:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

**Agent CRD with Memory**:
```yaml
spec:
  declarative:
    memory:
      modelConfig: text-embedding-ada-002  # OpenAI embeddings
      ttlDays: 30  # Auto-delete after 30 days
```

### How It Works

1. User sends message: "What was the CPU issue last week?"
2. Engine embeds query: `[0.123, 0.456, ...]`
3. Engine queries PostgreSQL: `SELECT * FROM memories WHERE embedding <-> query_embedding ORDER BY distance LIMIT 5`
4. Relevant past conversations retrieved
5. Added to LLM context as "Long-term memory"
6. LLM synthesizes answer using both current and past context

**Your Use Case**: With PostgreSQL already deployed, enable memory for:
- Incident history ("Did we see this error before?")
- Cost optimization trends ("What did we optimize last quarter?")
- GitOps patterns ("How did we handle that migration?")

---

## Context Compaction

### Problem

LLMs have token limits (e.g., 128k tokens for GPT-4). Long conversations exceed limits.

### Solution

Periodically summarize old messages to reduce context size.

**Configuration**:
```yaml
spec:
  declarative:
    context:
      compaction:
        compactionInterval: 5  # Compact every 5 messages
        modelConfig: gpt-4-mini  # Cheaper model for summaries
```

**Compaction Process**:
1. After 5 messages, agent detects context size growing
2. Oldest messages sent to compaction LLM: "Summarize this conversation segment"
3. Summary replaces original messages in context
4. Context size reduced while preserving semantic information

**Example**:
```
Before Compaction (10 messages, 8k tokens):
User: "Show me pod restarts"
Agent: [Uses QueryTool with 'rate(kube_pod_container_status_restarts_total[24h])']
Agent: "Pods nginx-abc and redis-xyz restarted"
User: "Why did nginx restart?"
Agent: [Checks Loki logs]
Agent: "OOMKilled due to memory limit"
...

After Compaction (1 message, 150 tokens):
Summary: "User investigated pod restarts. Found nginx-abc restarted due to OOMKilled (memory limit issue) and redis-xyz restarted from config change."
[Recent 5 messages preserved]
```

---

## OpenTelemetry Integration

### Built-in Support

kagent natively exports traces and logs to OpenTelemetry collectors.

**Your Infrastructure**: Already have Jaeger + OTel Collector deployed.

### Configuration

**Helm Values**:
```yaml
observability:
  enabled: true
  otelCollectorEndpoint: "http://opentelemetry-collector.observability.svc.cluster.local:4317"
```

**Trace Attributes**:
- `kagent.agent.name`: Agent name
- `kagent.session.id`: Session ID
- `kagent.tool.name`: Tool being called
- `kagent.model.provider`: LLM provider
- `kagent.model.name`: Model name

**Querying in Jaeger**:
```
service=kagent-engine operation=tool_call kagent.tool.name=QueryTool
```

**Your Use Cases**:
- Debug agent tool call failures
- Measure LLM latency by model
- Track cost (tokens used) per session
- Identify slow MCP servers
- Correlate agent actions with cluster events

---

## Controller Reconciliation Model

### Concurrency Strategy

**Sequential Reconciliation**: One reconciliation per CRD instance at a time to avoid race conditions.

**Why Not Parallel?**:
- Agents may have dependencies (A2A parent-child)
- Resource updates could conflict (e.g., updating same ConfigMap)
- Simpler debugging (linear event ordering)

**Impact**:
- Reconciliations are fast (<1s for most operations)
- Queue depth monitored via Prometheus metrics

### Garbage Collection

When an Agent CRD is deleted:
1. Controller deletes Deployment
2. Controller deletes Service
3. Controller deletes ConfigMaps
4. Controller preserves PostgreSQL data (memory) for TTL period

**Finalizers**: Ensure cleanup completes before CRD removal

---

## Security Considerations

### RBAC

**Agent Pod Service Account**:
- By default: `kagent-agent` SA with minimal cluster-reader permissions
- Customizable per-agent via Helm values: `controller.agentDeployment.serviceAccountName`

**Your Setup**:
- Observability agents need read access to Prometheus, Loki
- GitOps agents need read access to Flux CRDs
- Admin agents may need write access (use HITL!)

### Secrets Management

**ModelConfig API Keys**:
- Stored in Kubernetes Secrets
- Mounted as environment variables in agent pods
- Never logged or exposed in traces

**Your Integration**:
- Use External Secrets Operator (already deployed)
- Sync API keys from LocalStack Secrets Manager
- Rotate keys without redeploying agents

### Network Policies

**Isolate Agent Pods**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kagent-agent-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/managed-by: kagent
  policyTypes:
    - Egress
  egress:
    - to:  # Allow LLM API access
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
    - to:  # Allow MCP servers in same namespace
        - podSelector: {}
```

---

## What's Next?

- **[[02-Getting-Started]]** - Install kagent on your Flux CD cluster
- **[[03-Tools-and-MCP]]** - Detailed tool catalog for your stack
- **[[04-Agent-Patterns]]** - Real agent CRD examples
- **[[05-Production-Use-Cases]]** - Production deployment patterns

---

**Previous**: [[00-Overview]] | **Next**: [[02-Getting-Started]]
