# Promtail - Logging Agent

Log shipping agent collecting and forwarding logs from all cluster nodes to Loki.

## Purpose

- Log collection agent running on all cluster nodes
- Ships container and system logs to Loki aggregation system
- Label enrichment for log metadata and filtering
- Real-time log forwarding with minimal resource overhead

## Dependencies

- **Depends on**: loki (requires Loki instance for log forwarding and storage)
- **Parallel with**: Other logging and monitoring components
