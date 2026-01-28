# Redis Sentinel - High Availability In-Memory Database

Redis with Sentinel architecture providing high availability, automatic failover, and RDB snapshot persistence.

## Purpose

- In-memory key-value store for caching and fast data access
- High availability with Sentinel architecture and automatic failover
- RDB snapshot persistence (saves every 3 hours if at least 1 key changed)
- Session storage for web applications
- Pub/Sub messaging capabilities
- LRU eviction policy for cache workload optimization

## Architecture

### Redis Sentinel
- **Master-Replica replication** with automatic failover
- **Sentinel nodes** monitor master and replicas for health
- **Automatic failover**: Sentinel promotes a replica if master fails
- **Service discovery**: Master service tracks current master for clients

### Persistence Strategy
- **RDB snapshots**: Point-in-time snapshots every 3 hours
- **No AOF**: Disabled for better performance (cache workload)
- **Compression**: RDB files compressed for storage efficiency
- **Crash recovery**: Data restored from last snapshot on restart

## Dependencies

- **Depends on**: external-secrets-config (requires ClusterSecretStore for password management)
- **Depended on by**: redisinsight (Redis management interface)

## Configuration

### Key Settings
- **maxmemory**: Configurable memory limit with LRU eviction
- **Sentinel monitoring**: Configurable timeout and failover settings
- **Replication**: Configurable number of replicas
- **Resources**: Separate resource limits for master, replicas, and sentinels

### Service Endpoints
- `redis-sentinel-master`: Always points to current master (recommended for writes)
- `redis-sentinel-replicas`: Load-balanced read replicas
- `redis-sentinel`: Sentinel service for monitoring

## Connecting to Redis

```bash
# Connect to master (for writes)
redis-cli -h redis-sentinel-master.redis-sentinel.svc.cluster.local -p 6379

# Connect to replicas (for reads)
redis-cli -h redis-sentinel-replicas.redis-sentinel.svc.cluster.local -p 6379

# Check replication status
redis-cli -h redis-sentinel-master.redis-sentinel.svc.cluster.local -p 6379 info replication
```

## Port Forwarding

```bash
# Forward master port
kubectl port-forward -n redis-sentinel svc/redis-sentinel-master 6379:6379

# Forward sentinel port
kubectl port-forward -n redis-sentinel svc/redis-sentinel 26379:26379
```