GitOps infrastructure platform to manage 10+ services across multi-environment Kubernetes clusters with automated deployment, monitoring, and high availability. Used to host personal projects on local machine and quick POCs

# How to set up

### Start Docker Engine

- Adjust configuration for colima `vi ~/.colima/default/colima.yaml`
- 4 CPU and 8 GB RAM recommended
- Run `colima start`
- Check status with `colima list`

### Create Kind Cluster

- Run `kind create cluster --config kind-config.yaml`
- Verify creation with `kind get clusters` and `kubectl get nodes`

### Bootstrap Flux on the Cluster

- Install flux controllers on your cluster
- Connect Flux to your GitHub repo
- Track the `develop` branch
- Deploy everything in `clusters/stages/dev/clusters/services-amer`

```bash
flux bootstrap github \
    --owner=<your-github-username> \
    --repository=fleet-infra \
    --branch=develop \
    --path=./clusters/stages/dev/clusters/services-amer \
    --personal
```

### Wait for Flux to Deploy Everything

- `flux get all --watch`
- `flux get kustomizations`
- `flux get helmreleases -A`

### Run post-setup scripts

- Fix controlplane IP (if needed): `make fix-control-plane`
- Initialize AWS Secrets in LocalStack: `make init-aws-secrets`
- Verify services are starting properly: `make verify-startup``

### Start Port Forwarding

- `make port-forward`
