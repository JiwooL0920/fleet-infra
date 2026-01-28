# Redis to Redis Sentinel Migration Summary

## Overview
Successfully migrated from basic Redis deployment to Redis Sentinel architecture with improvements from production workload patterns.

## Key Improvements

### 1. High Availability Architecture
- **Redis Sentinel enabled**: Automatic failover and monitoring
- **Master-Replica replication**: Improved data availability
- **Service discovery**: Master service always points to current master
- **Automatic failover**: Sentinel promotes replica if master fails

### 2. Persistence Strategy
- **RDB snapshots**: Point-in-time backups every 3 hours (10800 seconds)
- **Compression**: `rdbcompression yes` for storage efficiency
- **Checksum**: `rdbchecksum yes` for data integrity
- **AOF disabled**: Better performance for cache workloads
- **No stop on save error**: `stop-writes-on-bgsave-error no` for availability

### 3. Memory Management
- **Configurable maxmemory**: Environment-specific memory limits
  - Dev: 1800Mi (90% of 2Gi limit)
  - Prod: 900Mi (90% of 1Gi limit)
- **LRU eviction policy**: `allkeys-lru` for cache workload optimization
- **Resource isolation**: Separate limits for master, replicas, and sentinels

### 4. Local Development Optimizations
- **Removed ECR registry references**: Uses public Bitnami images
- **Soft pod anti-affinity**: Works on single-node clusters
- **Removed node affinity/tolerations**: Simplified for local development
- **Removed autoscaling**: Static replica count for predictability
- **Optional metrics**: Disabled by default, enabled in prod

## Configuration Changes

### New Environment Variables

#### Base Configuration (`base/services/environment.env`)
```bash
REDIS_CHART_VERSION=20.7.0
REDIS_MAXMEMORY=450Mi
REDIS_SENTINEL_DOWN_AFTER_MILLISECONDS=30000
REDIS_SENTINEL_FAILOVER_TIMEOUT=180000
REDIS_SENTINEL_PARALLEL_SYNCS=1
REDIS_SENTINEL_MEM_REQ=64Mi
REDIS_SENTINEL_MEM_LIM=128Mi
REDIS_SENTINEL_CPU_REQ=50m
REDIS_SENTINEL_CPU_LIM=200m
REDIS_METRICS_ENABLED=false
```

#### Dev Environment (`clusters/stages/dev/clusters/services-amer/environment.env`)
```bash
REDIS_REPLICA_COUNT=1
REDIS_MAXMEMORY=1800Mi  # 90% of 2Gi limit
REDIS_METRICS_ENABLED=false
```

#### Prod Environment (`clusters/stages/prod/clusters/services-amer/environment.env`)
```bash
REDIS_REPLICA_COUNT=2
REDIS_MAXMEMORY=900Mi  # 90% of 1Gi limit
REDIS_METRICS_ENABLED=true
```

### Namespace Change
- Old: `redis`
- New: `redis-sentinel`

### Service Names
- Master (writes): `redis-sentinel-master.redis-sentinel.svc.cluster.local:6379`
- Replicas (reads): `redis-sentinel-replicas.redis-sentinel.svc.cluster.local:6379`
- Sentinel: `redis-sentinel.redis-sentinel.svc.cluster.local:26379`

## File Changes

### Created/Modified Files
```
✓ apps/base/redis-sentinel/
  ✓ namespace.yaml          (updated namespace to redis-sentinel)
  ✓ externalsecret.yaml     (updated namespace to redis-sentinel)
  ✓ helmrelease.yaml        (improved configuration, removed ECR/node affinity)
  ✓ kustomization.yaml      (unchanged)
  ✓ README.md               (updated with Sentinel architecture details)

✓ base/services/
  ✓ redis-sentinel.yaml     (new service kustomization)
  ✓ kustomization.yaml      (updated to reference redis-sentinel.yaml)
  ✓ environment.env         (added new Redis Sentinel variables)

✓ clusters/stages/dev/clusters/services-amer/
  ✓ environment.env         (added dev-specific Redis Sentinel variables)

✓ clusters/stages/prod/clusters/services-amer/
  ✓ environment.env         (added prod-specific Redis Sentinel variables)

✓ scripts/
  ✓ port-forward.sh         (updated namespace and service name)
  ✓ validate-config-simple.sh (updated validation for Redis Sentinel)
```

### Deleted Files
```
✗ apps/base/redis/
  ✗ All files deleted (replaced by redis-sentinel)

✗ base/services/redis.yaml (replaced by redis-sentinel.yaml)
```

## Deployment Changes

### Health Checks
Updated to monitor StatefulSets instead of Deployments:
- `redis-sentinel-master` StatefulSet
- `redis-sentinel-replicas` StatefulSet
- `redis-password` Secret

### Service Dependencies
Unchanged - still depends on `external-secrets-config`

## Connection Examples

### From Application Pods
```bash
# Master connection (for writes)
redis-cli -h redis-sentinel-master.redis-sentinel.svc.cluster.local -p 6379

# Replica connection (for reads)
redis-cli -h redis-sentinel-replicas.redis-sentinel.svc.cluster.local -p 6379
```

### Port Forwarding (Local Development)
```bash
# Via script
make port-forward

# Manual
kubectl port-forward -n redis-sentinel svc/redis-sentinel-master 6379:6379
```

### Check Replication Status
```bash
kubectl port-forward -n redis-sentinel svc/redis-sentinel-master 6379:6379
redis-cli -p 6379 info replication
```

### Check Sentinel Status
```bash
kubectl port-forward -n redis-sentinel svc/redis-sentinel 26379:26379
redis-cli -p 26379 sentinel master mymaster
redis-cli -p 26379 sentinel replicas mymaster
redis-cli -p 26379 sentinel sentinels mymaster
```

## Testing Checklist

- [ ] Validate configuration: `./scripts/validate-config-simple.sh`
- [ ] Deploy to dev: Commit to `develop` branch
- [ ] Verify pods running: `kubectl get pods -n redis-sentinel`
- [ ] Check StatefulSets: `kubectl get statefulsets -n redis-sentinel`
- [ ] Verify services: `kubectl get svc -n redis-sentinel`
- [ ] Test master connection: Port forward and connect with redis-cli
- [ ] Check replication status: `redis-cli info replication`
- [ ] Verify persistence: Check for `dump.rdb` files in master/replica pods
- [ ] Test failover: Delete master pod and verify replica promotion
- [ ] Verify RedisInsight connectivity: Check if it can connect to Redis

## Migration Benefits

1. **High Availability**: Automatic failover with minimal downtime
2. **Data Persistence**: RDB snapshots protect against pod restarts
3. **Performance**: Optimized for cache workloads with LRU eviction
4. **Resource Efficiency**: Better memory management with configurable limits
5. **Monitoring**: Production-ready with optional metrics export
6. **Local Development**: Simplified configuration works on single-node clusters
7. **Production Ready**: Proven configuration from production workload

## Next Steps

1. Test the deployment in development environment
2. Monitor Redis performance and adjust `maxmemory` if needed
3. Consider enabling metrics in dev for monitoring setup
4. Update application connection strings to use new service names
5. Document failover procedures for operations team
