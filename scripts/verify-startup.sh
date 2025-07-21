#!/bin/bash

echo "🔍 Verifying service startup order and health..."

# Check if Flux is running
echo "1. Checking Flux controllers..."
kubectl get pods -n flux-system | grep -E "(Running|Ready)"

# Check LocalStack (should start first)
echo "2. Checking LocalStack..."
kubectl get pods -n localstack -o wide
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=localstack -n localstack --timeout=120s

# Check PostgreSQL cluster
echo "3. Checking PostgreSQL cluster..."
kubectl get cluster -n cnpg-system
kubectl get pods -n cnpg-system -o wide
kubectl wait --for=condition=ready pod -l cnpg.io/cluster=postgresql-cluster -n cnpg-system --timeout=180s

# Check database connectivity
echo "4. Testing database connectivity..."
kubectl run pg-test -n cnpg-system --rm --restart=Never -it --image=postgres:16 -- \
  psql -h postgresql-cluster-rw -U app -d appdb -c "SELECT version();" || echo "Database connection failed"

# Check dependent services
echo "5. Checking N8N..."
kubectl get pods -n n8n -o wide
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=n8n -n n8n --timeout=120s || echo "N8N not ready"

echo "6. Checking Temporal..."
kubectl get pods -n temporal -o wide
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=temporal -n temporal --timeout=120s || echo "Temporal not ready"

# Check all services
echo "7. Overall service status:"
kubectl get pods --all-namespaces | grep -v kube-system | grep -v flux-system

# Check Flux reconciliation status
echo "8. Flux reconciliation status:"
flux get all

echo "✅ Startup verification complete!"