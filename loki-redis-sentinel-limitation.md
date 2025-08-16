# Loki Redis Sentinel Authentication Limitation

## Overview

This document details a critical compatibility issue between Grafana Loki v6.16.0 (Loki app v3.1.1) and Redis Sentinel authentication when using Redis as a cache backend. The issue prevents Loki from connecting to authenticated Redis Sentinel instances, limiting security options in production deployments.

## Problem Statement

**Core Issue**: Loki's Redis cache configuration does not support Sentinel authentication (`sentinel_password`), only Redis data server authentication (`password`). This creates a mismatch with security best practices that recommend enabling authentication on all Redis Sentinel instances.

**Error Manifestation**:
```
redis: 2025/08/16 20:49:18 sentinel.go:514: sentinel: GetMasterAddrByName master="mymaster" failed: NOAUTH Authentication required.
level=error caller=redis_cache.go:32 msg="error connecting to redis" name=frontend.redis err="redis: all sentinels specified in configuration are unreachable"
```

## Technical Background

### Redis Sentinel Authentication Architecture

In a properly secured Redis Sentinel deployment, there are **two distinct authentication layers**:

1. **Sentinel Authentication**: Controls access to Sentinel API endpoints for master discovery
   - Configured via `requirepass` directive in Sentinel configuration
   - Used by clients to query Sentinel for current master location
   - Authentication command: `AUTH <sentinel-password>`

2. **Redis Data Server Authentication**: Controls access to actual Redis data servers
   - Configured via `requirepass` directive in Redis server configuration  
   - Used by clients to read/write data after master discovery
   - Authentication command: `AUTH <redis-password>`

### Loki's Redis Cache Configuration

Loki's current Redis cache configuration supports only Redis data server authentication:

```yaml
cache:
  redis:
    endpoint: redis.redis.svc.cluster.local:26379
    master_name: mymaster
    password: "${REDIS_PASSWORD}"        # ✅ Supported: Redis server auth
    # sentinel_password: "${SENTINEL_PASSWORD}"  # ❌ NOT Supported: Sentinel auth
    db: 0
    expiration: 1h
    timeout: 500ms
    pool_size: 10
    idle_timeout: 90s
    max_connection_age: 10m
    route_randomly: true
```

### go-redis Client Capability vs Loki Implementation

The underlying [go-redis client](https://github.com/redis/go-redis) that Loki uses **does support** Sentinel authentication through the `FailoverOptions` struct:

```go
// go-redis supports both authentication types
rdb := redis.NewFailoverClient(&redis.FailoverOptions{
    MasterName:       "mymaster",
    SentinelAddrs:    []string{":26379"},
    Password:         "redis-password",      // ✅ Redis server auth
    SentinelPassword: "sentinel-password",   // ✅ Sentinel auth
})
```

However, **Loki's Redis cache wrapper does not expose the `SentinelPassword` parameter**, limiting it to only Redis server authentication.

## Investigation Timeline

### Initial Configuration Attempt

**File**: `/Users/jiwoolee/Project/fleet-infra/apps/base/redis/helmrelease.yaml`

Attempted to disable Sentinel authentication using Bitnami Redis Helm chart parameters:

```yaml
# Authentication configuration
auth:
  enabled: true
  sentinel: false                    # Attempt 1: Disable Sentinel auth
  existingSecret: "redis-password"
  existingSecretPasswordKey: "password"

# Redis Sentinel configuration  
sentinel:
  enabled: true
  masterSet: "mymaster"
  usePassword: false                 # Attempt 2: Alternative parameter
```

### Verification of Configuration

Despite configuration changes, Sentinel still requires authentication:

```bash
$ kubectl exec -n redis redis-node-0 -c sentinel -- cat /opt/bitnami/redis-sentinel/etc/sentinel.conf | grep -E "(requirepass|auth)"

sentinel auth-pass mymaster admin
requirepass "admin"
```

**Result**: Both `auth.sentinel: false` and `sentinel.usePassword: false` parameters failed to disable Sentinel authentication in the Bitnami Redis Helm chart v20.3.0.

### Loki Error Analysis

Loki logs show consistent authentication failures:

```
level=warn ts=2025-08-16T20:49:18.405187813Z caller=experimental.go:22 msg="experimental feature in use" feature="Redis cache - frontend.redis"
level=error ts=2025-08-16T20:49:18.406284943Z caller=redis_cache.go:32 msg="error connecting to redis" name=frontend.redis err="redis: all sentinels specified in configuration are unreachable"

redis: 2025/08/16 20:49:18 sentinel.go:514: sentinel: GetMasterAddrByName master="mymaster" failed: NOAUTH Authentication required.
```

Multiple cache layers affected:
- `frontend.redis`
- `frontend.index-stats-results-cache.redis` 
- `frontend.volume-results-cache.redis`
- `frontend.series-results-cache.redis`
- `frontend.label-results-cache.redis`
- `store.index-cache-read.redis`
- `store.index-cache-write.redis`
- `chunksredis`

## Security vs Compatibility Trade-offs

### Security Best Practices (Redis Official Recommendation)

According to [Redis Sentinel documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/):

> **Sentinels by default run without authentication.** This is usually fine in trusted environments, however, if you want to provide authentication to Sentinels you need to add authentication.

For production environments, Redis recommends:
1. Enable `requirepass` on all Sentinel instances
2. Use the same password for inter-Sentinel communication
3. Ensure clients authenticate to Sentinel before master discovery

### Current Limitation Impact

**Security Implications**:
- ❌ Sentinel instances remain unauthenticated, exposing master discovery API
- ❌ Potential for unauthorized Sentinel queries and topology discovery  
- ✅ Redis data servers remain properly authenticated

**Operational Implications**:
- ✅ Loki can connect to Redis for caching functionality
- ✅ Cache performance benefits available (results, chunks, index queries)
- ❌ Reduced overall security posture

## Attempted Solutions

### 1. Bitnami Redis Helm Chart Configuration

**Parameters Tested**:
```yaml
auth:
  sentinel: false      # Official parameter per Bitnami docs
  
sentinel:
  usePassword: false   # Alternative parameter found in research
  auth:
    enabled: false     # Nested auth configuration
```

**Result**: None of these parameters successfully disabled Sentinel authentication in chart version 20.3.0.

### 2. Helm Release Recreation

Attempted forcing Helm chart upgrade by:
1. Deleting HelmRelease resource: `kubectl delete helmrelease redis -n flux-system`
2. Forcing Flux reconciliation: `flux reconcile kustomization redis`
3. Verifying new Helm release deployment

**Result**: New Helm release created (revision 1) but Sentinel configuration unchanged.

### 3. Direct Pod Configuration Verification

Verified configuration inside running containers:
```bash
kubectl exec -n redis redis-node-0 -c sentinel -- cat /opt/bitnami/redis-sentinel/etc/sentinel.conf
```

**Observation**: Configuration file still contains `requirepass "admin"` despite Helm chart parameters.

## Workaround Analysis

### Option 1: Disable Sentinel Authentication (Current Approach)

**Pros**:
- ✅ Immediate Loki compatibility
- ✅ Maintains Redis data server authentication
- ✅ Preserves high availability through Sentinel

**Cons**:
- ❌ Reduces security posture
- ❌ Exposes Sentinel API without authentication
- ❌ Bitnami chart parameters not working as expected

### Option 2: Direct Redis Connection (Alternative)

**Configuration**:
```yaml
cache:
  redis:
    endpoint: redis-master.redis.svc.cluster.local:6379  # Direct master connection
    password: "${REDIS_PASSWORD}"
    # Remove master_name to disable Sentinel discovery
```

**Pros**:
- ✅ Bypasses Sentinel authentication issue entirely
- ✅ Maintains Redis server authentication
- ✅ Simpler configuration

**Cons**:
- ❌ Loses high availability benefits
- ❌ No automatic failover during master failures
- ❌ Manual intervention required for Redis failures

### Option 3: Wait for Loki Enhancement (Future)

**Requirements**:
- Add `sentinel_password` parameter to Loki's Redis cache configuration
- Expose go-redis client's `SentinelPassword` option
- Update documentation and examples

**Timeline**: Unknown - would require Loki enhancement request/pull request

## Related Issues and References

### Loki GitHub Issues

1. **[Issue #11564](https://github.com/grafana/loki/issues/11564)**: "Unreachable Redis Sentinel in Loki"
   - Similar connectivity issues with Redis Sentinel
   - Suggested workaround: Increase `redis.timeout` from default 500ms
   - Status: Unresolved

2. **[Pull Request #7270](https://github.com/grafana/loki/pull/7270)**: "Add support for username to redis cache configuration"
   - Added username authentication support
   - Does not address Sentinel authentication

### Bitnami Redis Chart Issues

1. **[Issue #3366](https://github.com/bitnami/charts/issues/3366)**: "go client fails to connect to Sentinel and AUTH is enabled"
   - Confirms client connectivity issues with authenticated Sentinels
   - Various chart configuration attempts documented

### Redis Community Discussion

1. **[Redis Forum](https://forum.redis.io/t/how-to-disable-sentinel-password-only-authentication/1907)**: "How to Disable Sentinel Password-only Authentication"
   - Community discussion on disabling Sentinel auth
   - Mixed recommendations based on security requirements

## Environment Details

### Infrastructure Configuration

**Kubernetes Environment**:
- Platform: Local development (Colima/kind)
- Flux CD: GitOps deployment with wave-based architecture
- Namespace: `redis` for Redis deployment, `monitoring` for Loki

**Redis Deployment**:
- Chart: `bitnami/redis` v20.3.0
- Redis Version: 7.4.1
- Architecture: `replication` (master/replica with Sentinel)
- Deployment: 1 master + 2 replicas with 2 Sentinel instances

**Loki Deployment**:
- Chart: `grafana/loki` v6.16.0  
- Loki Version: 3.1.1
- Mode: `SingleBinary` deployment
- Cache Configuration: Multi-layer Redis caching (4 databases)

### Network Configuration

**Service Discovery**:
```
Redis Sentinel: redis.redis.svc.cluster.local:26379
Redis Master: redis-master.redis.svc.cluster.local:6379
Redis Replica: redis-replica.redis.svc.cluster.local:6379
```

**Port Forwarding** (for testing):
```bash
kubectl port-forward -n redis svc/redis 26379:26379  # Sentinel
kubectl port-forward -n redis svc/redis 6380:6379    # Redis
kubectl port-forward -n monitoring svc/monitoring-loki 3100:3100  # Loki
```

## Configuration Files

### Current Loki Configuration

**File**: `/Users/jiwoolee/Project/fleet-infra/apps/base/loki/helmrelease.yaml`

```yaml
# Query range configuration with caching
query_range:
  align_queries_with_step: true
  cache_results: true
  results_cache:
    cache:
      redis:
        endpoint: redis.redis.svc.cluster.local:26379
        master_name: mymaster
        password: "${REDIS_PASSWORD}"
        db: 0
        expiration: 1h
        timeout: 500ms
        pool_size: 10
        idle_timeout: 90s
        max_connection_age: 10m
        route_randomly: true

# Additional cache configurations
chunk_store_config:
  chunk_cache_config:
    redis:
      endpoint: redis.redis.svc.cluster.local:26379
      master_name: mymaster
      password: "${REDIS_PASSWORD}"
      db: 1
      # ... additional settings

  write_dedupe_cache_config:
    redis:
      endpoint: redis.redis.svc.cluster.local:26379
      master_name: mymaster  
      password: "${REDIS_PASSWORD}"
      db: 2
      # ... additional settings

storage_config:
  index_queries_cache_config:
    redis:
      endpoint: redis.redis.svc.cluster.local:26379
      master_name: mymaster
      password: "${REDIS_PASSWORD}"
      db: 3
      # ... additional settings
```

### Current Redis Configuration  

**File**: `/Users/jiwoolee/Project/fleet-infra/apps/base/redis/helmrelease.yaml`

```yaml
values:
  # Enable Redis Sentinel architecture
  architecture: replication
  
  # Authentication configuration  
  auth:
    enabled: true
    sentinel: false                    # ❌ Not working
    existingSecret: "redis-password"
    existingSecretPasswordKey: "password"

  # Redis Sentinel configuration
  sentinel:
    enabled: true
    masterSet: "mymaster"
    downAfterMilliseconds: 30000
    failoverTimeout: 180000
    parallelSyncs: 1
    usePassword: false                 # ❌ Not working
```

## Recommendations

### Short-term Solution (Current Implementation)

1. **Accept the security trade-off** for development/testing environments
2. **Continue investigating** Bitnami chart parameters or alternative charts
3. **Monitor Loki functionality** with current Redis configuration
4. **Document security implications** for production deployment decisions

### Long-term Solutions

1. **Contribute to Loki**: Submit enhancement request for Sentinel authentication support
2. **Alternative Redis Deployment**: Investigate non-Bitnami charts with better Sentinel auth control
3. **Security Mitigation**: Implement network-level security (firewalls, network policies) to compensate
4. **Hybrid Approach**: Use direct Redis connections for critical services, Sentinel for non-critical

### Production Considerations

For production deployments, consider:

1. **Risk Assessment**: Evaluate whether unauthenticated Sentinel exposure is acceptable
2. **Network Security**: Implement strict network policies around Redis namespace
3. **Monitoring**: Add alerting for Redis connectivity and security events
4. **Documentation**: Clearly document security trade-offs for operational teams

## Conclusion

The incompatibility between Loki's Redis cache implementation and Redis Sentinel authentication represents a significant limitation for security-conscious deployments. While workarounds exist, they involve trade-offs between security and functionality.

The root cause lies in Loki's Redis cache wrapper not exposing the go-redis client's Sentinel authentication capabilities, despite the underlying client library supporting this functionality.

**Current Status**: Loki successfully connects to Redis with Sentinel authentication disabled, providing cache functionality but at reduced security posture.

**Next Steps**: Continue monitoring for Loki enhancements or alternative deployment strategies that can provide both security and functionality.

---

**Document Created**: 2025-08-16  
**Last Updated**: 2025-08-16  
**Environment**: Development (fleet-infra repository)  
**Status**: Active Issue - Monitoring for Resolution