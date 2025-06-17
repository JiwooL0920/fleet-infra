# Creating local kind clusters manually

- You must create the kind cluster first (manually or with a script)
- Flux and Kustomize manage resources inside the cluster, not the cluster itself.

```shell
kind create cluster --name services-amer-<ENV> --config kind-cluster-<ENV>.yaml
```
