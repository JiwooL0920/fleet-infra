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
- `redis-sentinel-headless`: Headless service for Sentinel discovery
- `redis-sentinel`: Sentinel service for monitoring (port 26379)

Applications should use Sentinel-aware Redis clients that automatically discover the master through Sentinel.

## Connecting to Redis

### Using Sentinel-Aware Clients (Recommended)

Applications should use Redis clients with Sentinel support that automatically discover the master:

```bash
# Sentinel endpoints
redis-sentinel.redis-sentinel.svc.cluster.local:26379

# Master set name
mymaster
```

### Direct Connection (for testing)

```bash
# Find current master via Sentinel
redis-cli -h redis-sentinel.redis-sentinel.svc.cluster.local -p 26379 sentinel get-master-addr-by-name mymaster

# Connect directly to a node (use headless service)
redis-cli -h redis-sentinel-node-0.redis-sentinel-headless.redis-sentinel.svc.cluster.local -p 6379

# Check replication status
redis-cli -h redis-sentinel-node-0.redis-sentinel-headless.redis-sentinel.svc.cluster.local -p 6379 info replication
```

## Port Forwarding

```bash
# Forward to first Redis node
kubectl port-forward -n redis-sentinel redis-sentinel-node-0 6379:6379

# Forward sentinel port
kubectl port-forward -n redis-sentinel svc/redis-sentinel 26379:26379

# Query Sentinel for master
redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

## Authentication

Redis Sentinel is configured **without authentication** for simplicity. This is suitable for:
- Local development environments
- Internal/private networks
- Testing and prototyping

For production deployments requiring authentication, enable `auth.enabled: true` and configure passwords via External Secrets.