#!/bin/bash

echo "Starting port forwards..."

# --- localstack ---
# [4566] LocalStack
echo "Port forwarding LocalStack on port 4566..."
kubectl port-forward -n localstack svc/localstack 4566:4566 &

# --- n8n---
# [5678] n8n
echo "Port forwarding n8n on port 5678..."
kubectl port-forward -n n8n svc/n8n 5678:80 &

# --- kube-prometheus-stack ---
# [3030] Grafana
echo "Port forwarding Grafana on port 3030..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3030:80 &

# [9090] Prometheus
echo "Port forwarding Prometheus on port 9090..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# [9093] Alertmanager
echo "Port forwarding Alertmanager on port 9093..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093 &

# [9100] Node Exporter
echo "Port forwarding Node Exporter on port 9100..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus-node-exporter 9100:9100 &

# --- weave-gitops ---
# [9001] Weave GitOps
echo "Port forwarding Weave GitOps on port 9001..."
kubectl port-forward -n weave-gitops svc/weave-gitops 9001:9001 &

# --- postgresql ---
# [5432] PostgreSQL
echo "Port forwarding PostgreSQL on port 5432..."
kubectl port-forward -n cnpg-system svc/postgresql-cluster-rw 5432:5432 &

# --- temporal ---
# [8090] Temporal UI
echo "Port forwarding Temporal UI on port 8090..."
kubectl port-forward -n temporal svc/temporal-server-web 8090:8080 &

echo "All port forwards started. Press Ctrl+C to stop all."

# Wait for all background processes
wait
