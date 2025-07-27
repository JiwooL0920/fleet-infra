#!/bin/bash

echo "Starting port forwards..."

# Function to check if a service exists
check_service() {
    local namespace=$1
    local service=$2
    kubectl get svc -n "$namespace" "$service" &>/dev/null
}

# Function to kill processes using a specific port
kill_port() {
    local port=$1
    local pids=$(lsof -ti:$port 2>/dev/null)
    if [ ! -z "$pids" ]; then
        echo "Killing existing processes on port $port..."
        echo $pids | xargs kill -9 2>/dev/null
        sleep 1
    fi
}

# Function to start port forward with error handling
start_port_forward() {
    local namespace=$1
    local service=$2
    local local_port=$3
    local remote_port=$4
    local description=$5
    
    if check_service "$namespace" "$service"; then
        # Kill any existing processes on this port
        kill_port "$local_port"
        echo "Port forwarding $description on port $local_port..."
        kubectl port-forward -n "$namespace" "svc/$service" "$local_port:$remote_port" &
    else
        echo "Skipping $description - service $service not found in namespace $namespace"
    fi
}

# --- localstack ---
start_port_forward "localstack" "localstack" "4566" "4566" "LocalStack"

# --- n8n (optional - may not be deployed) ---
start_port_forward "n8n" "n8n" "5678" "80" "n8n"

# --- kube-prometheus-stack ---
start_port_forward "monitoring" "monitoring-kube-prometheus-stack-grafana" "3030" "80" "Grafana"
start_port_forward "monitoring" "monitoring-kube-prometheus-prometheus" "9090" "9090" "Prometheus"
start_port_forward "monitoring" "monitoring-kube-prometheus-alertmanager" "9093" "9093" "Alertmanager"
start_port_forward "monitoring" "monitoring-kube-prometheus-stack-prometheus-node-exporter" "9100" "9100" "Node Exporter"

# --- weave-gitops ---
start_port_forward "weave-gitops" "weave-gitops" "9001" "9001" "Weave GitOps"

# --- postgresql ---
start_port_forward "cnpg-system" "postgresql-cluster-rw" "5432" "5432" "PostgreSQL"

# --- temporal ---
start_port_forward "temporal" "temporal-server-web" "8090" "8080" "Temporal UI"

# --- pgadmin4 ---
start_port_forward "pgadmin4" "pgadmin4" "8080" "80" "pgAdmin4"

# --- redis ---
start_port_forward "redis" "redis" "6379" "6379" "Redis"

# --- redisinsight ---
start_port_forward "redisinsight" "redisinsight" "8001" "80" "RedisInsight"

echo ""
echo "Port forwards started successfully!"
echo ""
echo "Available services:"
echo "  LocalStack:    http://localhost:4566"
echo "  n8n:           http://localhost:5678"
echo "  Grafana:       http://localhost:3030"
echo "  Prometheus:    http://localhost:9090"
echo "  Alertmanager:  http://localhost:9093"
echo "  Node Exporter: http://localhost:9100"
echo "  Weave GitOps:  http://localhost:9001"
echo "  PostgreSQL:    localhost:5432"
echo "  Temporal UI:   http://localhost:8090"
echo "  pgAdmin4:      http://localhost:8080"
echo "  Redis:         localhost:6379"
echo "  RedisInsight:  http://localhost:8001"
echo ""
echo "Press Ctrl+C to stop all port forwards."

# Wait for all background processes
wait
