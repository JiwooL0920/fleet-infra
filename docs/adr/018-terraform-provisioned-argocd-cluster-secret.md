# ADR-018: Terraform-Provisioned Argo CD Cluster Secret for Local Spoke

**Status:** Accepted
**Date:** 2026-07-03

## Context

ADR-013 established an Argo CD hub–spoke topology where the hub cluster runs Argo CD and a
separate spoke cluster hosts application workloads. For Argo CD on the hub to manage
workloads on the spoke, the hub needs credentials to the spoke's Kubernetes API.

The original registration mechanism (per ADR-013) was:

1. Manual one-time bootstrap via `make register-app-cluster`
2. The script mints a long-lived ServiceAccount token on the spoke
3. Token is stored in LocalStack Secrets Manager at `argocd/clusters/dev-applications`
4. An `ExternalSecret` on the hub syncs the token into a Kubernetes Secret with the
   `argocd.argoproj.io/secret-type: cluster` label
5. Argo CD auto-registers the spoke via that Secret

This works, but has real drawbacks:

- **Manual bootstrap step**: `make register-app-cluster` must be run once per fresh
  cluster. Easy to forget, blocks first-time setup, doesn't self-heal.
- **Chicken-and-egg ordering**: The script requires {hub reachable, spoke reachable,
  LocalStack up, Flux reconciled, ExternalSecret deployed} before it can succeed. Ordering
  failures produce confusing errors.
- **Bootstrap credential in a mock secrets manager**: LocalStack is a dev-only fixture.
  The pattern doesn't translate cleanly to cloud environments.
- **Token lifetime + rotation**: Manually minted tokens are long-lived (30 days). Rotation
  requires re-running the script; no automatic mechanism.

## Enterprise-Standard Pattern (for reference)

In production cloud environments (EKS/GKE/AKS), the established pattern for cross-cluster
Argo CD registration is workload identity federation with **no long-lived tokens anywhere**:

- Argo CD on the hub runs with cloud-native workload identity (IRSA on EKS,
  Workload Identity on GKE, Managed Identity on AKS). Its ServiceAccounts
  (`argocd-server`, `argocd-application-controller`, `argocd-applicationset-controller`)
  are annotated with a hub-side IAM role ARN.
- Each spoke cluster provisions a dedicated IAM role trusting the hub's identity, with
  permissions to authenticate to the spoke's Kubernetes API via the cloud's IAM auth
  plugin (`aws-iam-authenticator` for EKS, etc.).
- The Argo CD Cluster Secret contains only the spoke's API endpoint and the IAM role ARN
  to assume — no bearer token material. Credentials are minted per-request via STS (or
  the cloud equivalent), typically with 15-minute TTL.
- The Cluster Secret is committed to Git as a plain YAML manifest — no `ExternalSecret`
  indirection is needed because no secret material is stored (an IAM role ARN is not
  sensitive).
- Provisioning of the trust relationship (IAM roles, `aws-auth` ConfigMap entries) is
  done in the same Terraform code that creates the clusters themselves, giving one
  provisioning pipeline and one source of truth.

Example (EKS spoke, illustrative):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-spoke
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: my-spoke
  server: https://<spoke-eks-endpoint>
  config: |
    {
      "awsAuthConfig": {
        "clusterName": "my-spoke",
        "roleARN": "arn:aws:iam::<account>:role/<hub>-argocd-client-remote"
      },
      "tlsClientConfig": {"insecure": true}
    }
```

## Decision

For this repository's **local development environment** (Kind clusters, no cloud IAM
provider available), adopt the closest possible analog to the enterprise pattern:

### Constraint

Kind clusters do not participate in AWS/GCP/Azure IAM federation. There is no STS
equivalent for cross-cluster authentication in a purely local setup. Therefore
`awsAuthConfig`-style zero-token registration is not feasible for a Kind spoke, and a
short-lived bearer token minted from a spoke ServiceAccount remains the only option.

### Adapted pattern

1. **Provisioning tool owns cluster registration end-to-end**. Terraform (in the sibling
   `terraform-infra` repository) is already responsible for creating both the hub and
   spoke Kind clusters. After creation it also:
   - Uses the `kubernetes` provider (spoke context) to create an `argocd-manager`
     ServiceAccount + ClusterRoleBinding on the spoke.
   - Uses `kubernetes_token_request_v1` to mint a bearer token for that ServiceAccount.
   - Uses a second `kubernetes` provider instance (hub context) to create the Argo CD
     Cluster Secret directly on the hub, using `kubernetes_secret_v1` with the
     `argocd.argoproj.io/secret-type: cluster` label.

2. **Fleet-infra no longer contains a manifest for the spoke Cluster Secret.**
   The Secret is Terraform-owned. Flux does not touch it (Flux's `prune: true` only
   removes resources it previously applied — Terraform-provisioned resources are outside
   Flux's inventory and are safe from pruning).

3. **The manual bootstrap script and Makefile target are removed.** The operation is
   part of `terraform apply` and invisible to end users.

### Illustrative Terraform snippet (for `terraform-infra`)

```hcl
provider "kubernetes" {
  alias          = "hub"
  config_context = "kind-dev-services-amer"
}
provider "kubernetes" {
  alias          = "spoke"
  config_context = "kind-dev-applications"
}

resource "kubernetes_service_account_v1" "argocd_manager" {
  provider = kubernetes.spoke
  metadata {
    name      = "argocd-manager"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd_manager" {
  provider = kubernetes.spoke
  metadata { name = "argocd-manager-cluster-admin" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    namespace = kubernetes_service_account_v1.argocd_manager.metadata[0].namespace
  }
}

resource "kubernetes_token_request_v1" "argocd" {
  provider = kubernetes.spoke
  metadata {
    name      = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    namespace = kubernetes_service_account_v1.argocd_manager.metadata[0].namespace
  }
  spec {
    audiences           = ["https://kubernetes.default.svc"]
    expiration_seconds  = 2592000
  }
}

resource "kubernetes_secret_v1" "spoke_cluster" {
  provider = kubernetes.hub
  metadata {
    name      = "dev-applications"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }
  string_data = {
    name   = "dev-applications"
    server = "https://dev-applications-control-plane:6443"
    config = jsonencode({
      bearerToken     = kubernetes_token_request_v1.argocd.token
      tlsClientConfig = { insecure = true }
    })
  }
}
```

### Ownership boundary

| Resource | Owner |
|---|---|
| Kind clusters (hub + spoke) | Terraform (`terraform-infra`) |
| Spoke `argocd-manager` ServiceAccount + ClusterRoleBinding | Terraform |
| Spoke bearer token | Terraform (via `kubernetes_token_request_v1`) |
| Argo CD Cluster Secret on hub (`dev-applications`) | Terraform (via `kubernetes_secret_v1`) |
| Argo CD HelmRelease + Argo CD server config | Flux (this repository) |
| Argo CD `Application` CRs (app-of-apps) | Flux (this repository) |

## Consequences

### Positive

- **Zero manual bootstrap steps** for spoke cluster registration. `terraform apply` fully
  provisions both clusters and their inter-cluster authentication.
- **Aligned with production**: The Cluster Secret pattern (label + JSON config) matches
  what real cloud environments use. Migration to EKS/GKE/AKS in the future changes only
  the credential mechanism inside the JSON (`bearerToken` → `awsAuthConfig` etc.), not
  the overall flow.
- **Single ownership** for the credential path — the Cluster Secret has one clear owner
  (Terraform), eliminating the multi-hop indirection of the previous approach.
- **Fewer moving parts**: Removes the bootstrap script, the LocalStack seed for
  `argocd/clusters/dev-applications`, the ExternalSecret manifest, and one manual step
  from onboarding.

### Negative

- **Terraform state contains a bearer token**: The `kubernetes_token_request_v1` result is
  stored in Terraform state. This is acceptable for local dev where state lives on the
  developer's disk; for shared or CI-executed Terraform, state must be encrypted (remote
  backend with server-side encryption + strict IAM on state access).
- **Token rotation requires `terraform apply`**: Token lifetime is set by
  `expiration_seconds` (default 3600, max 2592000 = 30 days). Rotation happens on next
  `terraform apply` — either manually or scheduled.
- **Cross-repository coupling**: Fleet-infra assumes Terraform creates the Cluster Secret
  with the correct name (`dev-applications`), namespace (`argocd`), and label
  (`argocd.argoproj.io/secret-type: cluster`). Divergence causes silent Argo CD
  registration failure. Mitigated by documenting the contract in this ADR and in
  the fleet-infra README.

### Neutral

- **Kind + no cloud IAM**: The bearer-token-in-Secret pattern is a local-dev compromise.
  If the environment gains cloud-IAM equivalence in the future (migration to real cloud
  dev environment, adoption of a LocalStack IAM/STS emulation tier, or a SPIFFE/SPIRE
  local deployment), this ADR should be re-evaluated in favor of workload identity
  federation with no long-lived tokens.

## Migration Steps Taken (This ADR)

- Deleted `scripts/register-app-cluster.sh`.
- Removed the `register-app-cluster` target and help entry from `Makefile`.
- Deleted
  `clusters/stages/dev/clusters/services-amer/argocd-config/argocd-clusters/dev-applications.yaml`
  (the ExternalSecret manifest).
- Updated `clusters/stages/dev/clusters/services-amer/argocd-config/kustomization.yaml`
  to drop the resource entry.
- Updated `README.md` and `CLAUDE.md` operational sections to remove references to
  `make register-app-cluster` and to point to this ADR for the current registration flow.

## References

- ADR-005: LocalStack + External Secrets for Development Secrets — the general
  ExternalSecrets pattern that this ADR intentionally bypasses for the specific
  cross-cluster credential case.
- ADR-013: Argo CD Hub–Spoke for Application Workloads — the hub-spoke topology that this
  ADR refines. The topology is unchanged; only the registration mechanism changes.
- Argo CD Cluster Secret spec:
  <https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters>
- `kubernetes_token_request_v1` Terraform resource:
  <https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/token_request_v1>
