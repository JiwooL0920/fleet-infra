#!/usr/bin/env bash

# Setup Local DNS Entries for Traefik Ingress
# This script adds .local domain entries to /etc/hosts for accessing services via Traefik

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# DNS entries to add
HOSTS_ENTRIES=(
  "127.0.0.1 traefik.local"
  "127.0.0.1 grafana.local"
  "127.0.0.1 prometheus.local"
  "127.0.0.1 alertmanager.local"
  "127.0.0.1 n8n.local"
  "127.0.0.1 temporal.local"
  "127.0.0.1 pgadmin.local"
  "127.0.0.1 redis.local"
  "127.0.0.1 weave.local"
  "127.0.0.1 argocd.local"
  "127.0.0.1 localstack.local"
  "127.0.0.1 scylla.local"
  "127.0.0.1 jaeger.local"
  "127.0.0.1 kagent.local"
  "127.0.0.1 opencost.local"
  "127.0.0.1 agentgateway.local"
)

# Marker to identify our entries
MARKER="# Kubernetes local services via Traefik"

echo -e "${GREEN}Setting up local DNS entries for Traefik ingress...${NC}"
echo ""

# Check if entries already exist
if grep -q "$MARKER" /etc/hosts 2>/dev/null; then
  echo -e "${YELLOW}DNS entries already exist in /etc/hosts${NC}"
  echo "Entries found:"
  grep -A 20 "$MARKER" /etc/hosts
  echo ""
  read -p "Do you want to remove and re-add them? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Removing existing entries...${NC}"
    # Remove marker and next 14 lines (our entries)
    sudo sed -i.bak "/$MARKER/,+16d" /etc/hosts
    echo -e "${GREEN}Existing entries removed${NC}"
  else
    echo -e "${GREEN}Keeping existing entries. Exiting.${NC}"
    exit 0
  fi
fi

# Add entries
echo -e "${GREEN}Adding DNS entries to /etc/hosts...${NC}"
{
  echo ""
  echo "$MARKER"
  for entry in "${HOSTS_ENTRIES[@]}"; do
    echo "$entry"
  done
} | sudo tee -a /etc/hosts > /dev/null

echo ""
echo -e "${GREEN}✓ DNS entries added successfully!${NC}"
echo ""
echo "You can now access services via Traefik at:"
echo -e "${YELLOW}  http://traefik.local${NC} - Traefik Dashboard"
echo -e "${YELLOW}  http://grafana.local${NC} - Grafana"
echo -e "${YELLOW}  http://prometheus.local${NC} - Prometheus"
echo -e "${YELLOW}  http://alertmanager.local${NC} - AlertManager"
echo -e "${YELLOW}  http://n8n.local${NC} - N8N"
echo -e "${YELLOW}  http://temporal.local${NC} - Temporal UI"
echo -e "${YELLOW}  http://pgadmin.local${NC} - pgAdmin4"
echo -e "${YELLOW}  http://redis.local${NC} - RedisInsight"
echo -e "${YELLOW}  http://weave.local${NC} - Weave GitOps"
echo -e "${YELLOW}  http://argocd.local${NC} - Argo CD (spoke app sync)"
echo -e "${YELLOW}  http://localstack.local${NC} - LocalStack"
echo -e "${YELLOW}  http://scylla.local${NC} - ScyllaDB Alternator (DynamoDB API)"
echo -e "${YELLOW}  http://jaeger.local${NC} - Jaeger Tracing UI"
echo -e "${YELLOW}  http://kagent.local${NC} - kagent AI Agent Dashboard"
echo -e "${YELLOW}  http://opencost.local${NC} - OpenCost Cost Monitoring"
echo -e "${YELLOW}  http://agentgateway.local${NC} - AgentGateway (A2A + MCP Federation)"
echo ""
echo -e "${GREEN}Note:${NC} Make sure Traefik is configured with NodePort and Flux has reconciled the changes."
