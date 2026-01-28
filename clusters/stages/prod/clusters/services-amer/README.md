# Production Services Cluster (Americas)

Production cluster configuration for application services and infrastructure in the Americas region.

## Cluster Configuration

- **Cluster Name**: `services-amer-prod`
- **Environment**: `production` 
- **Git Branch**: Tracks `main` branch
- **Sync Interval**: 10 minutes
- **Resource Profile**: Performance-optimized

## Environment-Specific Configuration

This cluster uses environment-specific configuration overlays for optimal production performance:

### Configuration Files

- **environment.env**: Production-specific configuration values and resource allocations
- **cluster-vars-patch.yaml**: Cluster-specific overrides and metadata
- **kustomization.yaml**: Main kustomization with environment-specific settings

### Production Optimizations

**Resource Allocation:**
- Higher CPU and memory limits
- Multiple replicas for high availability
- Larger storage allocations
- Extended cache and retention periods

**Performance Tuning:**
- Optimized JVM settings for Java applications
- Enhanced database connection pools
- Increased buffer sizes and timeouts
- Production-grade caching configurations

**High Availability:**
- Multi-replica deployments
- Pod anti-affinity rules
- Node placement constraints
- Automated failover configurations

## Deployment Process

1. **Change Detection**: Flux CD monitors `main` branch
2. **Configuration Merge**: Base + environment-specific overlays
3. **Variable Substitution**: Environment values injected into manifests
4. **Staged Deployment**: Services deployed following dependency order
5. **Health Validation**: Comprehensive health checks before marking ready
6. **Monitoring**: Real-time monitoring and alerting

## Rollback Procedures

- **Immediate Rollback**: Git revert + Flux force reconciliation
- **Service-Specific**: Individual service rollback with Helm
- **Emergency**: Manual kubectl application of known-good configurations

## Monitoring and Alerts

Production cluster includes enhanced monitoring:
- Resource utilization tracking
- Application performance monitoring  
- Configuration drift detection
- Deployment success/failure alerts
- Security and compliance monitoring