# Crossplane Implementation Plan for Fleet-Infra

## Executive Summary
This document outlines the phased implementation of Crossplane for GitOps-managed AWS infrastructure provisioning in the fleet-infra repository. The implementation follows the existing wave-based deployment architecture and integrates with current infrastructure components.

## Current State Analysis

### Wave-Based Architecture
- **Wave 1**: Infrastructure Core (Traefik, LocalStack)
- **Wave 2**: Infrastructure Operators (CNPG, External Secrets, Metrics Server)
- **Wave 3**: Infrastructure Configuration
- **Wave 4**: Database Workloads & Services
- **Wave 5**: Database UI Tools

### Key Integration Points
1. **External Secrets Operator**: Already deployed in Wave 2, manages AWS credentials
2. **LocalStack**: Provides AWS API simulation for development
3. **Flux CD**: GitOps orchestration with Kustomizations
4. **cluster-vars ConfigMap**: Environment-specific configuration

## Implementation Phases

### Phase 1: Core Crossplane Setup (Current)
**Objective**: Deploy Crossplane core components in Wave 2

**Deliverables**:
1. Crossplane Helm Release in `/apps/base/crossplane/`
2. Wave 2 integration in `/base/infrastructure/operators/`
3. Basic AWS provider configuration
4. ProviderConfig for AWS credentials integration
5. Environment-specific patches for dev/prod

**Technical Details**:
- Deploy Crossplane v1.18.x with Helm
- Install AWS Provider family (S3, IAM, EC2)
- Configure credential injection from External Secrets
- Set up LocalStack endpoint overrides for development

### Phase 2: Provider Configuration & Compositions
**Objective**: Create reusable infrastructure compositions

**Deliverables**:
1. S3 Bucket Composition with lifecycle policies
2. IAM Role/Policy Compositions
3. VPC/Subnet Compositions for networking
4. Security Group Compositions
5. Composition Functions (patch-and-transform)

**Technical Details**:
- XRD definitions for custom APIs
- Compositions using Pipeline mode
- Environment-specific patches (EU/US regions)
- Integration with cluster-vars for configuration

### Phase 3: Application Integration
**Objective**: Migrate existing infrastructure to Crossplane management

**Deliverables**:
1. S3 buckets for PostgreSQL backups (CNPG)
2. IAM roles for service accounts (IRSA)
3. Network resources for services
4. Migration scripts and documentation

**Technical Details**:
- Update CNPG backup configuration
- Create IAM roles for N8N, Temporal
- Document rollback procedures

### Phase 4: Advanced Features
**Objective**: Implement advanced Crossplane capabilities

**Deliverables**:
1. Multi-region support
2. Cost management tags
3. Drift detection and remediation
4. Observability integration (Prometheus metrics)

## Technical Architecture

### Directory Structure
```
apps/base/crossplane/
├── helmrelease.yaml           # Crossplane core deployment
├── kustomization.yaml          # Kustomize configuration
├── namespace.yaml              # crossplane-system namespace
├── providers/                  # Provider configurations
│   ├── aws-provider.yaml       # AWS provider installation
│   └── provider-config.yaml    # ProviderConfig with credentials
├── compositions/               # Reusable compositions
│   ├── s3-bucket/
│   ├── iam-role/
│   └── networking/
└── functions/                  # Composition functions
    └── patch-and-transform.yaml

base/infrastructure/operators/
├── crossplane.yaml             # Wave 2 Kustomization reference
└── kustomization.yaml          # Updated with Crossplane
```

### Dependency Management
```yaml
# Wave 2 Dependencies
dependsOn:
  - name: infrastructure-core    # LocalStack must be ready
  
# Crossplane Dependencies  
dependsOn:
  - name: external-secrets-operator  # For AWS credentials
```

### Environment Configuration

#### Development (LocalStack)
```yaml
aws:
  endpoint: http://localstack.localstack.svc.cluster.local:4566
  region: us-east-1
  credentials:
    source: Secret
    secretRef:
      name: aws-creds-localstack
```

#### Production (AWS)
```yaml
aws:
  region: ${AWS_REGION}
  credentials:
    source: InjectedIdentity  # Or IRSA
```

## Implementation Steps (Phase 1)

### Step 1: Create Crossplane Base Configuration
1. Create `/apps/base/crossplane/` directory
2. Add namespace.yaml for crossplane-system
3. Create HelmRepository and HelmRelease
4. Configure values for production readiness

### Step 2: Install AWS Providers
1. Create Provider resources for AWS family
2. Configure ProviderConfig with External Secrets
3. Add LocalStack endpoint overrides
4. Test provider health

### Step 3: Wave 2 Integration
1. Add crossplane.yaml to `/base/infrastructure/operators/`
2. Update kustomization.yaml resource list
3. Configure proper dependencies
4. Test wave deployment order

### Step 4: Environment-Specific Configuration
1. Add Crossplane variables to cluster-vars
2. Create dev/prod patches if needed
3. Configure LocalStack endpoints for dev
4. Test in development environment

### Step 5: Validation & Testing
1. Verify Crossplane pod health
2. Check provider installation status
3. Test AWS API connectivity
4. Create test S3 bucket resource
5. Document findings and issues

## Security Considerations

1. **Credential Management**:
   - Use External Secrets for AWS credentials
   - Implement least-privilege IAM policies
   - Rotate credentials regularly

2. **RBAC**:
   - Limit Crossplane service account permissions
   - Implement resource quotas
   - Use namespace isolation

3. **Network Security**:
   - Restrict egress to required AWS APIs
   - Use private endpoints where possible
   - Implement network policies

## Monitoring & Observability

1. **Metrics**:
   - Crossplane controller metrics
   - Provider reconciliation metrics
   - Resource creation/deletion metrics

2. **Alerts**:
   - Provider health alerts
   - Reconciliation failure alerts
   - Drift detection alerts

3. **Logging**:
   - Structured logging to Loki
   - Debug logs for troubleshooting
   - Audit logs for compliance

## Rollback Plan

1. **Phase 1 Rollback**:
   - Remove Crossplane from Wave 2
   - Delete CRDs and resources
   - Restore previous configuration

2. **Data Preservation**:
   - Export resource states before migration
   - Maintain infrastructure outside Crossplane initially
   - Gradual migration approach

## Success Criteria

### Phase 1 Success Metrics
- [ ] Crossplane deployed in Wave 2 successfully
- [ ] AWS provider health check passing
- [ ] LocalStack connectivity verified
- [ ] Test S3 bucket created via Crossplane
- [ ] External Secrets integration working
- [ ] No impact on existing infrastructure

### Long-term Success Metrics
- [ ] 100% of AWS infrastructure managed via Crossplane
- [ ] Reduced manual infrastructure changes
- [ ] Improved deployment consistency
- [ ] Faster infrastructure provisioning
- [ ] Complete GitOps workflow for infrastructure

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Provider API compatibility | Low | High | Test thoroughly in dev |
| LocalStack limitations | Medium | Low | Document unsupported features |
| Credential exposure | Low | High | Use External Secrets, RBAC |
| Resource drift | Medium | Medium | Implement drift detection |
| Learning curve | High | Low | Provide documentation, examples |

## Timeline

- **Week 1**: Phase 1 implementation and testing
- **Week 2**: Phase 2 compositions development
- **Week 3-4**: Phase 3 application integration
- **Week 5-6**: Phase 4 advanced features
- **Week 7-8**: Documentation and training

## Next Steps

1. Review and approve implementation plan
2. Begin Phase 1 implementation
3. Set up development environment testing
4. Schedule team training sessions
5. Create runbook documentation

## References

- [Crossplane Documentation](https://docs.crossplane.io/)
- [AWS Provider Documentation](https://marketplace.upbound.io/providers/upbound/provider-family-aws/)
- [Flux CD Integration Guide](https://fluxcd.io/flux/guides/helmreleases/)
- [External Secrets Operator](https://external-secrets.io/)