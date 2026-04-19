# Cluster Agent Onboarding

This directory implements the **A-OBS topology**: one `cluster-agent-{cluster}` per cluster
owning k8s + Flux + Helm + cluster-scoped observability tools, plus a shared fleet-only
`observability-agent`.

## Active overlays

| Overlay | Status | Cluster |
|---------|--------|---------|
| `services-amer/` | **Active** | dev-services-amer kind cluster |
| `platform-amer/` | Disabled | — |
| `platform-emea/` | Disabled | — |
| `edge-amer/` | Disabled | — |
| `edge-emea/` | Disabled | — |

## Onboarding a new cluster (3 steps)

### Step 1 — Enable agentgateway backends

In `apps/base/agentgateway/mcp/`:

1. Open `backend-k8s-{cluster}.yaml` and uncomment the entire `AgentgatewayBackend` resource.
2. Open `backend-helm-{cluster}.yaml` and uncomment the entire `AgentgatewayBackend` resource.
3. Update the `static.host` in both files if the new cluster's `kagent-tools` is at a different
   endpoint (e.g. a remote cluster exposed via ingress or VPN).
4. Add both files to `apps/base/agentgateway/mcp/kustomization.yaml` (uncomment the lines).

### Step 2 — Enable the cluster-agent overlay

In `apps/base/kagent/agents/kustomization.yaml`, uncomment the overlay line:

```yaml
- cluster-agent/{cluster}
```

The `cluster-agent-{cluster}` pod will be created in the `kagent` namespace after Flux reconciles.
Smoke-test via the kagent UI agent picker: send "list pods in kagent namespace" and verify
the response references `{cluster}` and returns in < 8s.

### Step 3 — Update coordinator routing rule

In `apps/base/kagent/agents/coordinator-agent.yaml`:

1. Add `- type: Agent` entry for `cluster-agent-{cluster}` in the tools list.
2. Add `{cluster}` to the cluster name set in routing rule 2 of the `systemMessage`.

Example diff:
```yaml
# tools:
- type: Agent
  agent:
    name: cluster-agent-{cluster}

# systemMessage rule 2:
   {services-amer, platform-amer, {cluster}}
```

After Flux reconciles, run the routing benchmark: send "Is Flux synced on {cluster}?" and
verify the coordinator routes to `cluster-agent-{cluster}` (not `observability-agent`).

## Adding ArgoCD tools to a cluster

1. Deploy the ArgoCD MCP server in the cluster's `argocd` namespace.
2. Uncomment `backend-argocd-{cluster}.yaml` in `agentgateway/mcp/kustomization.yaml`.
3. Uncomment the `/mcp/argo` rule in `agentgateway/mcp/route.yaml`.
4. Uncomment `argocd-federated.yaml` in `kagent/mcpservers/kustomization.yaml`.
5. Populate `tools[2].mcpServer.toolNames` in the cluster overlay with `argocd-{cluster}_*` names.

## Directory structure

```
cluster-agent/
├── README.md               ← this file
├── base/
│   ├── agent.yaml          ← Agent CR base (toolNames and systemMessage are placeholders)
│   └── kustomization.yaml
├── services-amer/
│   └── kustomization.yaml  ← JSON 6902 patches: name, labels, toolNames, systemMessage, skills
├── platform-amer/          ← disabled; uncomment in agents/kustomization.yaml to activate
│   └── kustomization.yaml
├── platform-emea/
│   └── kustomization.yaml
├── edge-amer/
│   └── kustomization.yaml
└── edge-emea/
    └── kustomization.yaml
```
