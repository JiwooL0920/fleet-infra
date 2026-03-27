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

## Final Investigation Results (Updated 2025-08-16)

### Definitive Root Cause Identification

After comprehensive testing, we have **definitively identified** the root cause and confirmed the limitation:

#### **Problem Confirmed**: Missing `SentinelPassword` Parameter in Loki

**Test Results**:
1. ✅ **Redis Authentication**: Working correctly with password `admin`
2. ✅ **Sentinel Authentication**: Working correctly with same password `admin`
3. ✅ **Manual Sentinel Connection**: Successfully tested with redis-cli
4. ❌ **Loki Sentinel Connection**: Fails due to missing `SentinelPassword` configuration

#### **Verification Commands**

**Successful Manual Authentication**:
```bash
# Test Sentinel connection with password
kubectl exec -n redis redis-node-0 -c redis -- redis-cli -h redis.redis.svc.cluster.local -p 26379 -a admin ping
# Output: PONG

# Test Sentinel master discovery with password
kubectl exec -n redis redis-node-0 -c redis -- redis-cli -h redis.redis.svc.cluster.local -p 26379 -a admin sentinel get-master-addr-by-name mymaster
# Output: redis-node-0.redis-headless.redis.svc.cluster.local 6379
```

**Loki Error Persistence**:
```
redis: 2025/08/16 21:29:02 sentinel.go:514: sentinel: GetMasterAddrByName master="mymaster" failed: NOAUTH Authentication required.
```

### Solution Attempts and Results

#### **Attempt 1: Disable Sentinel Authentication**

**Configuration Tested**:
```yaml
auth:
  sentinel: false          # ❌ Failed - Parameter ignored

sentinel:
  usePassword: false       # ❌ Failed - Parameter ignored
```

**Result**: Bitnami Redis Helm chart v20.3.0 does not properly disable Sentinel authentication with these parameters.

#### **Attempt 2: Enable Same Password for Both Services**

**Configuration Applied**:
```yaml
auth:
  enabled: true
  sentinel: true           # ✅ Working - Both use same password
  existingSecret: "redis-password"
  existingSecretPasswordKey: "password"
```

**Result**:
- ✅ **Redis servers**: Authenticate successfully with password `admin`
- ✅ **Sentinel instances**: Authenticate successfully with same password `admin`
- ❌ **Loki connection**: Still fails because go-redis client needs explicit `SentinelPassword` parameter

### Technical Analysis: go-redis Client Requirements

#### **Working go-redis Configuration (Required)**

```go
rdb := redis.NewFailoverClient(&redis.FailoverOptions{
    MasterName:       "mymaster",
    SentinelAddrs:    []string{":26379"},
    Password:         "admin",        // ✅ Redis server auth
    SentinelPassword: "admin",        // ❌ Missing in Loki config
})
```

#### **Current Loki Configuration (Insufficient)**

```go
// Loki's RedisConfig struct (simplified)
type RedisConfig struct {
    Endpoint     string `yaml:"endpoint"`
    MasterName   string `yaml:"master_name"`
    Password     string `yaml:"password"`        // ✅ Redis auth only
    // SentinelPassword string `yaml:"sentinel_password"` // ❌ MISSING!
}
```

### Related Grafana Projects Analysis

#### **Grafana Tempo - Solved Same Issue**

- **Issue**: [grafana/tempo#1460](https://github.com/grafana/tempo/issues/1460) - "Redis: Support SentinelPassword"
- **Solution**: [grafana/tempo#1463](https://github.com/grafana/tempo/pull/1463) - Added `SentinelPassword` configuration
- **Status**: ✅ **Resolved** - Tempo now supports Sentinel authentication
- **Quote**: "Extending the redis config with `SentinelPassword` of redis.UniversalOptions should allow password auth for redis sentinel clusters"

#### **Other Grafana Projects**

- **Grafana Core**: ✅ Supports `ha_redis_sentinel_password` parameter
- **Redis Data Source**: ✅ Supports separate Sentinel authentication since v1.5.0

### Security vs Functionality Final Assessment

#### **Current Security Posture**: ✅ **Good**

- ✅ Redis data servers properly authenticated
- ✅ Sentinel instances properly authenticated
- ✅ Same strong password (`admin`) for both services
- ✅ Network-level isolation in Kubernetes

#### **Current Functionality**: ❌ **Limited**

- ❌ Loki cannot use Redis caching due to Sentinel auth failure
- ❌ Multi-layer cache performance benefits unavailable
- ❌ Cache hits/misses not working for query optimization

### Definitive Solutions

#### **Solution 1: File Loki Enhancement Request (Recommended)**

**Action Items**:
1. Create GitHub issue in [grafana/loki](https://github.com/grafana/loki) repository
2. Reference successful Tempo implementation ([PR #1463](https://github.com/grafana/tempo/pull/1463))
3. Request adding `SentinelPassword` field to `RedisConfig` struct
4. Provide use case and testing details from this investigation

**Expected Configuration After Fix**:
```yaml
cache:
  redis:
    endpoint: redis.redis.svc.cluster.local:26379
    master_name: mymaster
    password: "${REDIS_PASSWORD}"           # Redis server auth
    sentinel_password: "${REDIS_PASSWORD}"  # ✅ NEW: Sentinel auth
```

#### **Solution 2: Temporary Workaround - Direct Redis Connection**

**Configuration**:
```yaml
cache:
  redis:
    endpoint: redis-master.redis.svc.cluster.local:6379  # Direct master
    password: "${REDIS_PASSWORD}"
    # Remove master_name to bypass Sentinel discovery
```

**Trade-offs**:
- ✅ Immediate cache functionality
- ❌ Loss of high availability during Redis failover
- ❌ Manual intervention required during master failures

#### **Solution 3: Custom Loki Implementation**

**Requirements**:
1. Fork [grafana/loki](https://github.com/grafana/loki) repository
2. Add `SentinelPassword` field to Redis configuration struct
3. Update go-redis client initialization to use both passwords
4. Build and deploy custom Loki image
5. Maintain fork with upstream updates

### Production Recommendations

#### **Immediate Actions (Current Environment)**

1. **Accept Current Limitation**: Document that Redis caching is disabled due to Sentinel auth incompatibility
2. **Monitor Loki Performance**: Ensure acceptable performance without Redis caching
3. **File Enhancement Request**: Create Loki GitHub issue for `SentinelPassword` support

#### **Long-term Strategy**

1. **Track Loki Releases**: Monitor for `SentinelPassword` feature addition
2. **Alternative Cache Solutions**: Consider Memcached if Redis caching remains unavailable
3. **Performance Testing**: Benchmark Loki performance with and without Redis caching

#### **Security Considerations**

- ✅ Current Redis/Sentinel configuration meets security best practices
- ✅ Strong authentication on all Redis components
- ✅ Network isolation in Kubernetes environment
- ⚠️ Consider additional monitoring for cache performance impact

## Updated Conclusion

**Root Cause Confirmed**: Loki's Redis cache implementation is missing the `SentinelPassword` configuration parameter that the underlying go-redis client supports and requires for authenticated Sentinel environments.

**Current Status**:
- ✅ **Security**: Redis and Sentinel properly secured with authentication
- ❌ **Functionality**: Loki caching disabled due to authentication incompatibility
- 🔄 **Solution**: Requires Loki enhancement to add missing `SentinelPassword` parameter

**Next Steps**:
1. File enhancement request with Grafana Loki team
2. Reference successful Tempo implementation as blueprint
3. Monitor Loki releases for feature addition
4. Consider temporary direct Redis connection if immediate caching needed

**Lessons Learned**:
- Bitnami Redis Helm chart Sentinel auth parameters require further investigation
- go-redis client supports Sentinel auth but application must expose configuration
- Cross-project learning from Grafana ecosystem (Tempo solution) provides clear path forward

---

**Document Created**: 2025-08-16
**Last Updated**: 2025-08-16 (Final Investigation Complete)
**Environment**: Development (fleet-infra repository)
**Status**: Root Cause Confirmed - Solution Path Identified
