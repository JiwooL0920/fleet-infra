#!/bin/bash

# fix-control-plane-ip.sh
# Comprehensive post-Colima restart recovery script
# Fixes control plane IP, DNS issues, webhook timeouts, and triggers Flux reconciliation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Post-Colima restart recovery script starting...${NC}"

# Function to check if kubectl is available and cluster is accessible
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster. Is the cluster running?${NC}"
        exit 1
    fi
}

# Function to check if this is a Kind cluster
check_kind_cluster() {
    if ! kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' | grep -q "kind://"; then
        echo -e "${YELLOW}⚠️  This doesn't appear to be a Kind cluster. Exiting.${NC}"
        exit 0
    fi
}

# Function to get control plane node name
get_control_plane_node() {
    kubectl get nodes --no-headers -l node-role.kubernetes.io/control-plane -o custom-columns=NAME:.metadata.name | head -n1
}

# Function to get control plane container name
get_control_plane_container() {
    local node_name=$1
    echo "${node_name}"
}

# Function to check if control plane node is NotReady
is_control_plane_not_ready() {
    local node_name=$1
    local status=$(kubectl get node "$node_name" --no-headers -o custom-columns=STATUS:.status.conditions[-1].type)
    [[ "$status" != "Ready" ]]
}

# Function to get current IP from container
get_container_current_ip() {
    local container_name=$1
    docker exec "$container_name" ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1
}

# Function to get kubelet config server IP
get_kubelet_config_ip() {
    local container_name=$1
    docker exec "$container_name" grep 'server:' /etc/kubernetes/kubelet.conf | sed 's/.*https:\/\/\([^:]*\):.*/\1/'
}

# Function to fix kubelet configuration
fix_kubelet_config() {
    local container_name=$1
    local old_ip=$2
    local new_ip=$3
    
    echo -e "${YELLOW}🔄 Updating kubelet configuration: ${old_ip} -> ${new_ip}${NC}"
    
    # Update kubelet.conf
    docker exec "$container_name" sed -i "s|server: https://${old_ip}:6443|server: https://${new_ip}:6443|" /etc/kubernetes/kubelet.conf
    
    # Restart kubelet
    echo -e "${YELLOW}🔄 Restarting kubelet service...${NC}"
    docker exec "$container_name" systemctl restart kubelet
    
    echo -e "${GREEN}✅ Kubelet configuration updated and service restarted${NC}"
}

# Function to wait for node to become Ready
wait_for_node_ready() {
    local node_name=$1
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}⏳ Waiting for control plane node to become Ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if ! is_control_plane_not_ready "$node_name"; then
            echo -e "${GREEN}✅ Control plane node is now Ready!${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}   Attempt ${attempt}/${max_attempts}: Node still not ready...${NC}"
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}❌ Control plane node did not become Ready within ${max_attempts} attempts${NC}"
    return 1
}

# Function to check and fix DNS issues
fix_dns_issues() {
    echo -e "${BLUE}🔍 Checking DNS (CoreDNS) health...${NC}"
    
    # Check if CoreDNS pods are running
    local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [[ $coredns_pods -lt 2 ]]; then
        echo -e "${YELLOW}⚠️  CoreDNS pods not running properly. Restarting...${NC}"
        kubectl rollout restart deployment/coredns -n kube-system || true
        sleep 10
    else
        echo -e "${GREEN}✅ CoreDNS pods are running${NC}"
    fi
}

# Function to fix webhook connectivity issues
fix_webhook_issues() {
    echo -e "${BLUE}🔍 Checking webhook health...${NC}"
    
    # Restart External Secrets webhook if it exists
    if kubectl get deployment secrets-manager-external-secrets-webhook -n secrets-manager &>/dev/null; then
        echo -e "${YELLOW}🔄 Restarting External Secrets webhook...${NC}"
        kubectl rollout restart deployment/secrets-manager-external-secrets-webhook -n secrets-manager
    fi
    
    # Restart CNPG operator if it exists
    if kubectl get deployment -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg &>/dev/null; then
        echo -e "${YELLOW}🔄 Restarting CNPG operator...${NC}"
        kubectl rollout restart deployment -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
    fi
    
    echo -e "${YELLOW}⏳ Waiting for webhooks to stabilize...${NC}"
    sleep 15
}

# Function to clean up crashing pods
cleanup_crashing_pods() {
    echo -e "${BLUE}🔍 Cleaning up crashing pods...${NC}"
    
    # Find and delete CrashLoopBackOff pods in kube-system (especially kube-proxy)
    local crashing_pods=$(kubectl get pods -n kube-system --no-headers | grep "CrashLoopBackOff" | awk '{print $1}' || true)
    
    if [[ -n "$crashing_pods" ]]; then
        echo -e "${YELLOW}🧹 Deleting crashing pods: $crashing_pods${NC}"
        echo "$crashing_pods" | xargs -r kubectl delete pod -n kube-system
        sleep 5
    else
        echo -e "${GREEN}✅ No crashing pods found${NC}"
    fi
}

# Function to trigger Flux reconciliation
trigger_flux_reconciliation() {
    echo -e "${BLUE}🔄 Triggering Flux reconciliation...${NC}"
    
    # Check if flux command is available
    if ! command -v flux &> /dev/null; then
        echo -e "${YELLOW}⚠️  Flux CLI not found. Skipping Flux reconciliation.${NC}"
        return 0
    fi
    
    # Reconcile Git source first
    echo -e "${YELLOW}🔄 Reconciling Git source...${NC}"
    flux reconcile source git flux-system --timeout=30s || true
    
    # Reconcile core kustomizations
    echo -e "${YELLOW}🔄 Reconciling core kustomizations...${NC}"
    flux reconcile kustomization flux-system --timeout=30s || true
    flux reconcile kustomization infrastructure-operators --timeout=30s || true
    
    # Suspend and resume problematic kustomizations to reset their state
    local problem_kustomizations="external-secrets-config database-workloads infrastructure-config"
    
    echo -e "${YELLOW}🔄 Resetting problematic kustomizations...${NC}"
    flux suspend kustomization $problem_kustomizations || true
    sleep 2
    flux resume kustomization $problem_kustomizations || true
    
    echo -e "${GREEN}✅ Flux reconciliation triggered${NC}"
}

# Function to wait for system stabilization
wait_for_system_stability() {
    echo -e "${BLUE}⏳ Waiting for system to stabilize...${NC}"
    
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local ready_kustomizations=$(flux get kustomizations 2>/dev/null | grep -c "True" || echo "0")
        local total_kustomizations=$(flux get kustomizations 2>/dev/null | grep -c "flux-system\|infrastructure\|database\|services" || echo "1")
        
        if [[ $ready_kustomizations -gt $((total_kustomizations / 2)) ]]; then
            echo -e "${GREEN}✅ System appears to be stabilizing (${ready_kustomizations}/${total_kustomizations} kustomizations ready)${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}   Attempt ${attempt}/${max_attempts}: ${ready_kustomizations}/${total_kustomizations} kustomizations ready...${NC}"
        sleep 10
        ((attempt++))
    done
    
    echo -e "${YELLOW}⚠️  System may still be stabilizing. Check with 'flux get all' or 'make verify-startup'${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Checking cluster accessibility...${NC}"
    check_kubectl
    
    echo -e "${BLUE}🔍 Verifying this is a Kind cluster...${NC}"
    check_kind_cluster
    
    echo -e "${BLUE}🔍 Getting control plane node information...${NC}"
    CONTROL_PLANE_NODE=$(get_control_plane_node)
    
    if [[ -z "$CONTROL_PLANE_NODE" ]]; then
        echo -e "${RED}❌ No control plane node found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}📍 Control plane node: ${CONTROL_PLANE_NODE}${NC}"
    
    # Check if control plane is already Ready
    if ! is_control_plane_not_ready "$CONTROL_PLANE_NODE"; then
        echo -e "${GREEN}✅ Control plane node is already Ready.${NC}"
        
        # Still perform light health checks and Flux reconciliation
        echo -e "${BLUE}🔍 Performing health checks and Flux reconciliation...${NC}"
        cleanup_crashing_pods
        trigger_flux_reconciliation
        
        echo -e "${GREEN}🎉 Health check and reconciliation completed!${NC}"
        echo -e "${BLUE}💡 Run 'make verify-startup' to check application health${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}⚠️  Control plane node is NotReady. Checking IP configuration...${NC}"
    
    CONTAINER_NAME=$(get_control_plane_container "$CONTROL_PLANE_NODE")
    
    # Get current and configured IPs
    CURRENT_IP=$(get_container_current_ip "$CONTAINER_NAME")
    CONFIG_IP=$(get_kubelet_config_ip "$CONTAINER_NAME")
    
    echo -e "${BLUE}📍 Container current IP: ${CURRENT_IP}${NC}"
    echo -e "${BLUE}📍 Kubelet config IP: ${CONFIG_IP}${NC}"
    
    if [[ "$CURRENT_IP" == "$CONFIG_IP" ]]; then
        echo -e "${YELLOW}⚠️  IP addresses match, but node is still NotReady. Running comprehensive recovery...${NC}"
        
        # Perform comprehensive recovery even without IP mismatch
        fix_dns_issues
        cleanup_crashing_pods
        fix_webhook_issues
        
        # Wait a bit for recovery
        echo -e "${YELLOW}⏳ Waiting for recovery to take effect...${NC}"
        sleep 20
        
        if wait_for_node_ready "$CONTROL_PLANE_NODE"; then
            echo -e "${GREEN}✅ Node recovered without IP fix!${NC}"
            trigger_flux_reconciliation
            wait_for_system_stability
            echo -e "${GREEN}🎉 Recovery completed successfully!${NC}"
            kubectl get nodes
            echo -e "${BLUE}💡 Run 'make verify-startup' to check application health${NC}"
        else
            echo -e "${RED}❌ Node still not ready after recovery attempts. Check system pods:${NC}"
            kubectl get pods -n kube-system --no-headers | grep -E "(apiserver|etcd|scheduler|controller)" || true
            exit 1
        fi
        return 0
    fi
    
    echo -e "${RED}🔧 IP mismatch detected! Fixing configuration...${NC}"
    fix_kubelet_config "$CONTAINER_NAME" "$CONFIG_IP" "$CURRENT_IP"
    
    # Wait for node to become Ready
    if wait_for_node_ready "$CONTROL_PLANE_NODE"; then
        echo -e "${GREEN}✅ Control plane IP fix completed!${NC}"
        
        # Perform additional recovery steps
        fix_dns_issues
        cleanup_crashing_pods
        fix_webhook_issues
        trigger_flux_reconciliation
        wait_for_system_stability
        
        echo -e "${GREEN}🎉 Post-Colima restart recovery completed successfully!${NC}"
        echo -e "${BLUE}📊 Final cluster status:${NC}"
        kubectl get nodes
        echo -e "${BLUE}💡 Run 'make verify-startup' to check application health${NC}"
    else
        echo -e "${RED}❌ Control plane node is still not Ready. Manual intervention may be required.${NC}"
        exit 1
    fi
}

# Handle script interruption
trap 'echo -e "\n${RED}❌ Script interrupted${NC}"; exit 1' INT TERM

# Run main function
main "$@"