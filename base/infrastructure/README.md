# Infrastructure - Karpenter Configuration

This directory contains Karpenter autoscaling configuration for **cloud environments only**.

## ⚠️ Important: Local Development

**Karpenter does NOT work in local KIND clusters** because:

1. **No Cloud Provider**: Karpenter requires AWS/Azure/GCP APIs to provision nodes
2. **KIND Uses Docker Containers**: KIND nodes are Docker containers, not real VMs
3. **Bottlerocket is Cloud-Only**: Bottlerocket is an AWS-optimized OS that doesn't run locally

### Local vs Cloud Deployment Strategy

```
Local (KIND):
└── Karpenter DISABLED (not deployed)

Cloud (EKS/AKS/GKE):
└── Karpenter ENABLED (deployed with cloud-specific configuration)
```

## Configuration Files

### `default-karpenter-resources.yaml`

Defines the default Karpenter NodePool and EC2NodeClass for AWS EKS with:

- **Bottlerocket AMI**: AWS-optimized container OS
- **Instance Types**: c5, m5 families (excluding metal)
- **Capacity Type**: On-demand instances
- **Security**: Encrypted EBS volumes, IMDSv2 required
- **Custom Certificates**: Company-specific root and technical CAs

## Environment Variables Used

```bash
${K8S_VERSION}                    # Kubernetes version for AMI selection
${BOTTLEROCKET_SNAPSHOT_ID_CPU}   # Pre-configured Bottlerocket snapshot
${EKS_CLUSTER_TYPE}               # Cluster type for tagging
${EKS_CLUSTER_REGION}             # AWS region
${CLUSTER_ENVIRONMENT}            # Environment (dev/staging/prod)
```

## Deployment Strategy

### For Cloud Environments (EKS)

1. **Install Karpenter Operator** (via Helm)
2. **Deploy NodePool and EC2NodeClass** (this configuration)
3. **Configure IAM Roles** for Karpenter controller
4. **Set up Interruption Handling** (AWS Node Termination Handler)

### For Local Development (KIND)

**Do NOT deploy Karpenter** - it won't work and will cause errors.

Instead:
- Use KIND's built-in nodes (pre-created)
- Test pod scheduling without autoscaling
- Mock Karpenter behavior if needed for testing

## How to Enable for Cloud

When deploying to cloud environments, you would:

1. **Create a cloud-specific overlay**:
   ```yaml
   # clusters/stages/prod-eks/infrastructure/kustomization.yaml
   resources:
     - ../../../base/infrastructure/default-karpenter-resources.yaml
   
   patches:
     - patch: |-
         - op: replace
           path: /spec/template/spec/requirements/0/values
           value: ["c6i", "m6i"]  # Use newer instance types
       target:
         kind: NodePool
         name: default
   ```

2. **Add environment-specific variables**:
   ```bash
   # clusters/stages/prod-eks/environment.env
   K8S_VERSION=1.28
   BOTTLEROCKET_SNAPSHOT_ID_CPU=snap-0123456789abcdef
   EKS_CLUSTER_TYPE=production
   EKS_CLUSTER_REGION=us-east-1
   CLUSTER_ENVIRONMENT=production
   ```

3. **Deploy Karpenter operator first** (as a dependency)

## Testing Locally (Simulation)

If you need to test Karpenter-like behavior locally:

1. **Use static node configurations**
2. **Mock scaling with kubectl scale**
3. **Test pod affinity/anti-affinity rules**
4. **Validate resource requests/limits**

## Next Steps for Cloud Deployment

1. [ ] Set up AWS IAM roles for Karpenter
2. [ ] Create EKS cluster with proper tags
3. [ ] Install Karpenter Helm chart
4. [ ] Deploy this configuration
5. [ ] Test with a sample workload
6. [ ] Monitor node provisioning in CloudWatch

## References

- [Karpenter Documentation](https://karpenter.sh/)
- [Bottlerocket Documentation](https://bottlerocket.dev/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
