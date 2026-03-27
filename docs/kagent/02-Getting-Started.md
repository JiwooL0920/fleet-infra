# Getting Started with kagent

**Previous**: [[01-Architecture]] | **Next**: [[03-Tools-and-MCP]]

---

## Prerequisites

Before installing kagent, ensure you have:

✅ **Kubernetes Cluster**: v1.27+ (you have: Colima with local cluster)
✅ **Flux CD**: Installed and operational (you have: deployed to `flux-system` namespace)
✅ **PostgreSQL**: v14+ with pgvector extension (you have: CloudNative PG cluster)
✅ **Storage**: PersistentVolume support (you have: via Colima)
✅ **Ingress**: Optional, for UI access (you have: Traefik with .local domains)

## Installation Methods

Three options for installing kagent:

1. **Helm (Direct)**: Quick testing, manual management
2. **Flux CD HelmRelease (Recommended)**: GitOps, automated reconciliation
3. **Flux CD with OCI Workaround**: Handles known OCI digest bug

We'll use **Option 2** since you have Flux CD deployed.

---

## Step 1: Prepare PostgreSQL Database

kagent requires a PostgreSQL database with pgvector extension.

### Create Database and User

```yaml
# apps/base/cloudnative-pg/databases/kagent-database.yaml
apiVersion: v1
kind: Secret
metadata:
  name: kagent-db-credentials
  namespace: cnpg-system
type: Opaque
stringData:
  username: kagent
  password: GENERATED_PASSWORD_HERE  # Use strong password

---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: kagent
  namespace: cnpg-system
spec:
  name: kagent
  owner: kagent
  cluster:
    name: postgresql-cluster
```

### Enable pgvector Extension

```bash
# Connect to PostgreSQL cluster
kubectl exec -it -n cnpg-system postgresql-cluster-1 -- psql -U postgres

# Switch to kagent database
\c kagent

# Create pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

# Verify
\dx vector

# Exit
\q
```

---

## Step 2: Create LLM API Key Secret

kagent needs credentials for your LLM provider.

### Option A: OpenAI API Key

```yaml
# base/services/kagent-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: openai-api-key
  namespace: kagent
type: Opaque
stringData:
  key: sk-YOUR_OPENAI_API_KEY_HERE
```

### Option B: Use Ollama (Local, No API Key)

If using Ollama (local model server), you don't need an API key.

**Deploy Ollama First**:
```yaml
# apps/base/ollama/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ollama
  namespace: ollama
spec:
  interval: 10m
  chart:
    spec:
      chart: ollama
      version: 0.60.0
      sourceRef:
        kind: HelmRepository
        name: ollama
        namespace: flux-system
  values:
    service:
      type: ClusterIP
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
```

**Ollama ModelConfig** (no API key needed):
```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: ollama-llama3
  namespace: kagent
spec:
  provider: Ollama
  model: llama3.1:8b
  openAI:
    baseUrl: http://ollama.ollama.svc.cluster.local:11434
  temperature: 0.7
```

### Option C: External Secrets Operator (Your Setup)

Since you have External Secrets Operator with LocalStack:

```yaml
# apps/base/kagent/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kagent-openai-key
  namespace: kagent
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: localstack-secretstore
    kind: ClusterSecretStore
  target:
    name: openai-api-key
    creationPolicy: Owner
  data:
    - secretKey: key
      remoteRef:
        key: kagent/openai/api-key
```

**Create Secret in LocalStack**:
```bash
# Port forward to LocalStack
kubectl port-forward -n localstack svc/localstack 4566:4566

# Create secret
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name kagent/openai/api-key \
  --secret-string "sk-YOUR_OPENAI_API_KEY" \
  --region us-east-1
```

---

## Step 3: Create Flux CD HelmRelease

### Add Helm Repository

```yaml
# clusters/stages/dev/clusters/services-amer/flux-system/sources/kagent-helm-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: kagent
  namespace: flux-system
spec:
  interval: 10m
  url: https://kagent-dev.github.io/kagent
```

### Create HelmRelease

```yaml
# apps/base/kagent/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kagent
  namespace: kagent
spec:
  interval: 10m
  timeout: 15m
  chart:
    spec:
      chart: kagent
      version: 0.2.x  # Use latest 0.2.x version
      sourceRef:
        kind: HelmRepository
        name: kagent
        namespace: flux-system

  install:
    crds: CreateReplace
    remediation:
      retries: 3

  upgrade:
    crds: CreateReplace
    remediation:
      retries: 3

  values:
    # Database Configuration (use your PostgreSQL cluster)
    database:
      postgres:
        url: "postgresql://kagent:GENERATED_PASSWORD@postgresql-cluster-rw.cnpg-system.svc.cluster.local:5432/kagent"
        vectorEnabled: true  # Enable pgvector for memory

    # Controller Configuration
    controller:
      image:
        repository: ghcr.io/kagent-dev/kagent
        tag: v0.2.32  # Match chart version

      replicas: 1

      # Agent Deployment Defaults
      agentDeployment:
        serviceAccountName: kagent-agent  # Default SA for agents
        podLabels:
          app.kubernetes.io/part-of: kagent

      # Watch all namespaces
      watchNamespaces: []  # Empty = watch all

    # UI Configuration
    ui:
      enabled: true
      replicas: 1

      service:
        type: ClusterIP
        port: 3000

      # Optional: Ingress via Traefik
      ingress:
        enabled: true
        className: traefik
        annotations:
          traefik.ingress.kubernetes.io/router.entrypoints: web
        hosts:
          - host: kagent.local
            paths:
              - path: /
                pathType: Prefix

    # Observability (integrate with your Jaeger + OTel)
    observability:
      enabled: true
      otelCollectorEndpoint: "http://opentelemetry-collector.observability.svc.cluster.local:4317"

    # Pre-installed Agents (disable for now, we'll create custom ones)
    agents:
      k8s-agent:
        enabled: false
      promql-agent:
        enabled: true  # Enable PromQL agent
      observability-agent:
        enabled: false  # We'll customize this
      istio-agent:
        enabled: false

    # MCP Tool Server (built-in Prometheus tools)
    toolServer:
      enabled: true
      prometheus:
        url: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
```

### Create Service Kustomization

```yaml
# base/services/kagent.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: kagent
  namespace: flux-system
spec:
  interval: 10m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/base/kagent
  prune: true
  wait: true
  timeout: 15m0s
  dependsOn:
    - name: cnpg-operator  # PostgreSQL cluster must exist
    - name: external-secrets-operator  # For API key secrets
    - name: traefik  # For ingress
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars
```

### Add to Main Kustomization

```yaml
# base/services/kustomization.yaml
resources:
  # ... existing services
  - kagent.yaml
```

---

## Step 4: Deploy to Cluster

### Commit and Push

```bash
# Stage changes
git add apps/base/kagent/
git add apps/base/cloudnative-pg/databases/kagent-database.yaml
git add base/services/kagent.yaml
git add clusters/stages/dev/clusters/services-amer/flux-system/sources/kagent-helm-source.yaml

# Commit
git commit -m "Add kagent with Flux CD integration"

# Push to develop branch (for dev environment)
git push origin develop
```

### Monitor Deployment

```bash
# Watch Flux reconciliation
flux get sources helm
flux get helmreleases -n kagent

# Watch kagent pods starting
kubectl get pods -n kagent -w

# Expected pods:
# - kagent-controller-xxx (controller)
# - kagent-ui-xxx (UI)
# - kagent-tool-server-xxx (built-in MCP tools)
# - promql-agent-xxx (if enabled)
```

### Verify Installation

```bash
# Check CRDs installed
kubectl get crd | grep kagent

# Expected CRDs:
# agents.kagent.dev
# modelconfigs.kagent.dev
# mcpservers.kagent.dev
# remotemcpservers.kagent.dev

# Check controller logs
kubectl logs -n kagent -l app.kubernetes.io/component=controller

# Check UI is accessible
curl http://kagent.local  # If using Traefik ingress
```

---

## Step 5: Create Your First ModelConfig

```yaml
# apps/base/kagent/modelconfigs/openai-gpt4.yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: gpt4-default
  namespace: kagent
spec:
  provider: OpenAI
  model: gpt-4o
  apiKeySecretRef: openai-api-key
  apiKeySecretKey: key
  temperature: 0.7
  maxTokens: 4096
```

**Apply**:
```bash
kubectl apply -f apps/base/kagent/modelconfigs/openai-gpt4.yaml

# Verify
kubectl get modelconfig -n kagent
```

---

## Step 6: Create Your First Agent

### Simple Kubernetes Query Agent

```yaml
# apps/base/kagent/agents/k8s-query-agent.yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-query-agent
  namespace: kagent
spec:
  type: Declarative
  description: "Query Kubernetes resources using natural language"

  declarative:
    modelConfig: gpt4-default

    systemMessage: |
      You are a Kubernetes expert assistant.
      You can query Kubernetes resources and provide information about the cluster.
      Current date: 2026-03-25

      When describing resources, include:
      - Name and namespace
      - Status (Running, Pending, Failed)
      - Key metadata (labels, annotations)
      - Resource usage if available

    runtime: python
    stream: true

    tools:
      - type: McpServer
        mcpServer:
          name: kagent-tool-server
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - k8s_get_resources
            - k8s_describe_resource
            - k8s_get_available_api_resources
```

**Apply**:
```bash
kubectl apply -f apps/base/kagent/agents/k8s-query-agent.yaml

# Wait for agent pod to start
kubectl get pods -n kagent -l kagent.dev/agent=k8s-query-agent -w

# Check logs
kubectl logs -n kagent -l kagent.dev/agent=k8s-query-agent
```

---

## Step 7: Access the UI

### Option A: Traefik Ingress (Your Setup)

If you ran `make setup-dns`:
```bash
# Open browser
open http://kagent.local
```

### Option B: Port Forward

```bash
# Forward UI port
kubectl port-forward -n kagent svc/kagent-ui 3000:3000

# Open browser
open http://localhost:3000
```

### Using the UI

1. **Select Agent**: Choose `k8s-query-agent` from dropdown
2. **Start Chat**: Type "List all pods in the kagent namespace"
3. **Observe**: Agent will:
   - Call `k8s_get_resources` tool
   - Process results
   - Return formatted list of pods

---

## Step 8: Test with kubectl (Alternative)

### Using Port Forward to Engine API

```bash
# Forward agent engine port
kubectl port-forward -n kagent svc/k8s-query-agent 8000:8000

# Send request via curl
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "List all pods in the kagent namespace"}
    ],
    "stream": false
  }'
```

---

## Troubleshooting

### Agent Pod Not Starting

**Check HelmRelease status**:
```bash
kubectl describe helmrelease kagent -n kagent
```

**Common Issues**:
1. **PostgreSQL connection failed**: Verify database URL and credentials
2. **API key secret not found**: Check secret exists: `kubectl get secret openai-api-key -n kagent`
3. **Image pull errors**: Check image repository and tag

### Agent Returns "Tool Not Found"

**Verify tool server is running**:
```bash
kubectl get pods -n kagent -l app.kubernetes.io/component=tool-server
kubectl logs -n kagent -l app.kubernetes.io/component=tool-server
```

**Check RemoteMCPServer exists**:
```bash
kubectl get remotemcpserver -n kagent
```

### Database Connection Issues

**Test PostgreSQL connectivity**:
```bash
# Port forward to PostgreSQL
kubectl port-forward -n cnpg-system svc/postgresql-cluster-rw 5432:5432

# Test connection
psql "postgresql://kagent:GENERATED_PASSWORD@localhost:5432/kagent" -c "SELECT version();"

# Verify pgvector extension
psql "postgresql://kagent:GENERATED_PASSWORD@localhost:5432/kagent" -c "\dx vector"
```

### Flux CD Known Issue: OCI Repository Bug

If you see errors like:
```
Error: failed to create resource: Deployment.apps "kagent-controller" is invalid:
spec.template.metadata.labels: Invalid value: "v0.2.32+sha256-abc123...":
must be no more than 63 characters
```

**Workaround**: Use HelmRepository instead of OCIRepository (already done in our example above).

**Alternative Workaround** (if using OCI):
```yaml
spec:
  chart:
    spec:
      chart: oci://ghcr.io/kagent-dev/kagent-chart
      version: 0.2.32
  postRenderers:
    - kustomize:
        patches:
          - target:
              kind: Deployment
            patch: |
              - op: replace
                path: /spec/template/metadata/labels/app.kubernetes.io~1version
                value: "0.2.32"
```

---

## Next Steps

Now that kagent is installed:

1. **[[03-Tools-and-MCP]]** - Explore available tools for your stack
2. **[[04-Agent-Patterns]]** - Build more sophisticated agents
3. **[[06-Your-Infrastructure]]** - Examples specific to your cluster

### Recommended Next Agents to Build

- **Observability Agent**: Query Prometheus + Loki together
- **Flux CD Troubleshooter**: Diagnose HelmRelease and Kustomization failures
- **Cost Optimizer**: Analyze resource requests vs usage
- **Security Auditor**: Check for misconfigurations

---

**Previous**: [[01-Architecture]] | **Next**: [[03-Tools-and-MCP]]
