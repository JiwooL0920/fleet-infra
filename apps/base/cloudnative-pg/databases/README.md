# Database Configurations

Application-specific database definitions automatically created within the PostgreSQL cluster.

## Purpose

- Defines databases created automatically by the CNPG operator
- Pre-configured databases for specific applications
- Database-specific configurations and settings
- Application database isolation and organization

## Databases

- `n8n.yaml` - Database for N8N workflow automation platform
- `temporal.yaml` - Database for Temporal workflow orchestration engine  
- `youtube-automation.yaml` - Database for YouTube automation workflows
- Additional application databases as needed

## Integration

These databases are automatically created when the PostgreSQL cluster is deployed and are immediately available for application connections.