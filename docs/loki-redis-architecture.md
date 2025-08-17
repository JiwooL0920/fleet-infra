# Loki Redis Integration Architecture

## Overview

This document outlines the comprehensive solution for Loki's Redis integration without Sentinel service discovery, addressing the limitation where Loki's Redis client doesn't support `SentinelPassword` authentication.

## Problem Analysis

### Root Cause
- **Sentinel Limitation**: Loki's Redis client lacks `SentinelPassword` support for Sentinel authentication
- **Service Load-Balancing**: Main Redis service `redis.redis.svc.cluster.local:6379` load-balances between ALL Redis nodes (master + read-only replicas)
- **Write Safety**: Critical write operations could be sent to read-only replicas, causing failures
- **Data Consistency**: Write deduplication cache must maintain consistency across Loki instances

### Current Redis Topology
- **redis-node-0**: Master (handles all writes)
- **redis-node-1**: Read-only replica
- **Main Service**: Load-balances between both nodes
- **Architecture**: Bitnami Redis Helm chart v20.3.0 with replication + Sentinel

## Solution: Service Segregation Strategy

### Architecture Design

```
┌─────────────────────────────────────────────────────┐
│                   Loki Caches                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Write-Critical Cache:                              │
│  • write_dedupe_cache_config (db: 2)               │
│    └─→ redis-master.redis.svc.cluster.local:6379   │
│        (MASTER ONLY - Data Consistency Critical)   │
│                                                     │
│  Read-Heavy Caches:                                 │
│  • results_cache (db: 0)                           │
│  • chunk_cache_config (db: 1)                      │
│  • index_queries_cache_config (db: 3)              │
│    └─→ redis.redis.svc.cluster.local:6379          │
│        (LOAD BALANCED - Performance Optimized)     │
│                                                     │
└─────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│               Kubernetes Services                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  redis-master.redis.svc.cluster.local:6379         │
│  └─→ Always routes to current Redis master         │
│      (Auto-updates during failover)                │
│                                                     │
│  redis.redis.svc.cluster.local:6379                │
│  └─→ Load-balances between master + replicas       │
│      (Read scaling + performance)                  │
│                                                     │
└─────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│                 Redis Cluster                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  redis-node-0 (Master)                             │
│  └─→ Handles all write operations                  │
│      Database consistency critical                 │
│                                                     │
│  redis-node-1 (Replica)                            │
│  └─→ Read-only operations                          │
│      Improves read performance                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Implementation Components

#### 1. Redis Configuration Changes
```yaml
# /apps/base/redis/helmrelease.yaml
sentinel:
  service:
    createMaster: true  # Creates dedicated master service
```

#### 2. Loki Cache Strategy
- **Write Deduplication Cache**: `redis-master` (master-only for consistency)
- **Query Results Cache**: `redis` (load-balanced for performance)
- **Chunk Metadata Cache**: `redis` (load-balanced for performance)  
- **Index Queries Cache**: `redis` (load-balanced for performance)

#### 3. Service Discovery
- **Master Service**: `redis-master.redis.svc.cluster.local:6379`
  - Automatically tracks current master
  - Updates during Redis failover
  - No manual intervention required
- **Load-Balanced Service**: `redis.redis.svc.cluster.local:6379`
  - Routes to master + replicas
  - Optimizes read performance

## Benefits

### 1. Write Safety
- Critical write operations guaranteed to reach master
- Prevents data inconsistency from failed replica writes
- Write deduplication maintains log integrity

### 2. Read Performance
- Read operations leverage both master and replicas
- Improved query performance through load distribution
- Reduced master load for read-heavy workloads

### 3. High Availability
- Master service automatically updates during failover
- No client-side Sentinel complexity
- Simplified connection management

### 4. Operational Simplicity
- Direct Redis connections (no Sentinel client)
- Standard Kubernetes service discovery
- Compatible with existing monitoring

## Cache Operation Patterns

### Write-Heavy Operations
- **write_dedupe_cache_config**: Prevents duplicate log ingestion
- **Pattern**: SET operations with expiration
- **Criticality**: Must maintain consistency across Loki instances
- **Routing**: Master-only service

### Read-Heavy Operations
- **results_cache**: Query result caching
- **chunk_cache_config**: Chunk metadata lookup
- **index_queries_cache_config**: Index search optimization
- **Pattern**: Mostly GET operations with occasional SET
- **Routing**: Load-balanced service for performance

## Failover Handling

### Redis Master Failover Process
1. **Sentinel Detection**: Detects master failure
2. **Failover Execution**: Promotes replica to master
3. **Service Update**: `redis-master` service automatically updates to new master
4. **Client Reconnection**: Loki reconnects to new master via service
5. **No Manual Intervention**: Process is fully automated

### Connection Resilience
- **Connection Pooling**: Maintains persistent connections
- **Timeout Configuration**: 500ms timeout prevents hanging
- **Retry Logic**: Built into Loki's Redis client
- **Circuit Breaking**: Automatic retry with exponential backoff

## Monitoring and Alerting

### Key Metrics to Monitor
```yaml
# Redis Master Connectivity
redis_master_connection_failures_total
redis_master_operation_duration_seconds

# Cache Performance
loki_cache_redis_request_duration_seconds
loki_cache_redis_request_total{status="success|error"}

# Write Deduplication Health
loki_write_dedupe_cache_operations_total
loki_write_dedupe_cache_errors_total
```

### Recommended Alerts
- Redis master connection failures
- Write deduplication cache errors
- Cache operation latency spikes
- Redis service endpoint changes

## Testing and Validation

### Verification Steps
1. **Service Creation**: Verify `redis-master` service is created
2. **Endpoint Validation**: Confirm service points to master pod
3. **Cache Operations**: Test write/read operations to different services
4. **Failover Testing**: Simulate master failure and verify service update

### Test Commands
```bash
# Verify Redis master service creation
kubectl get svc -n redis redis-master

# Test master connectivity
kubectl exec -n monitoring deployment/loki -- redis-cli -h redis-master.redis.svc.cluster.local -p 6379 -a $REDIS_PASSWORD ping

# Verify cache database assignments
kubectl exec -n monitoring deployment/loki -- redis-cli -h redis-master.redis.svc.cluster.local -p 6379 -a $REDIS_PASSWORD info keyspace

# Monitor Loki cache metrics
kubectl exec -n monitoring deployment/loki -- wget -qO- http://localhost:3100/metrics | grep loki_cache
```

## Rollback Procedures

### Emergency Rollback
1. **Revert Loki Configuration**: Restore all caches to main `redis` service
2. **Remove Master Service**: Set `sentinel.service.createMaster: false`
3. **Monitor Service Health**: Verify Redis connectivity
4. **Validate Cache Operations**: Confirm cache functionality

### Rollback Commands
```bash
# Quick rollback - point all caches to main service
kubectl patch helmrelease loki -n flux-system --type='merge' -p='{"spec":{"values":{"loki":{"structuredConfig":{"chunk_store_config":{"write_dedupe_cache_config":{"redis":{"endpoint":"redis.redis.svc.cluster.local:6379"}}}}}}}}'

# Force Flux reconciliation
flux reconcile helmrelease loki -n flux-system
```

## Security Considerations

### Password Management
- **Single Password**: Same password for all Redis connections
- **Secret Rotation**: Update `redis-password` secret as needed
- **TLS Support**: Can be enabled for encrypted connections

### Network Policies
- **Service Isolation**: Redis services restricted to Loki namespace
- **Pod-to-Pod Communication**: Secured through Kubernetes network policies
- **External Access**: Redis not exposed outside cluster

## Performance Optimization

### Connection Tuning
- **Pool Size**: Optimized per cache type (5-10 connections)
- **Idle Timeout**: 90s to balance resource usage
- **Max Connection Age**: 10m for connection refresh

### Cache Sizing
- **Database Separation**: Each cache type uses separate Redis database
- **Expiration Policies**: Tuned per cache type (10m-1h)
- **Memory Management**: Monitor Redis memory usage

## Future Improvements

### Potential Enhancements
1. **Read Replica Routing**: Explicit read-only replica targeting
2. **Cache Warming**: Pre-populate frequently accessed data
3. **Multi-Region Setup**: Geographic distribution for global deployments
4. **Advanced Monitoring**: Detailed cache hit/miss metrics

### Scaling Considerations
- **Horizontal Scaling**: Add more Redis replicas for read scaling
- **Vertical Scaling**: Increase Redis memory for larger caches
- **Cache Partitioning**: Split large caches across multiple instances

## Conclusion

This service segregation strategy provides a production-ready solution for Loki's Redis integration without Sentinel complexity. The approach ensures write safety, optimizes read performance, maintains high availability, and simplifies operational management while addressing the fundamental limitation of Loki's Redis client.

The solution is designed to be:
- **Safe**: Write operations guaranteed to reach master
- **Performant**: Read operations leveraging load balancing
- **Resilient**: Automatic failover handling
- **Simple**: Standard Kubernetes service discovery
- **Maintainable**: Clear separation of concerns