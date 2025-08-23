# Redis - Database Service

High-performance in-memory data store with secure authentication for caching and session management.

## Purpose

- In-memory key-value store for caching and fast data access
- Session storage for web applications
- Pub/Sub messaging capabilities
- Secure password authentication via External Secrets
- High availability configuration ready

## Dependencies

- **Depends on**: external-secrets-operator (requires ESO for secure password management)
- **Depended on by**: redisinsight (Redis management interface)