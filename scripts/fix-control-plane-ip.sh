#!/bin/bash

# fix-control-plane-ip.sh
# Fixes control plane IP configuration after Colima restart
# This script automatically detects and fixes IP mismatches between kubelet config and actual API server IP

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Control plane IP fix script starting...${NC}"

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
        echo -e "${GREEN}✅ Control plane node is already Ready. No action needed.${NC}"
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
        echo -e "${YELLOW}⚠️  IP addresses match, but node is still NotReady. This might be a different issue.${NC}"
        echo -e "${YELLOW}   Checking system pods...${NC}"
        kubectl get pods -n kube-system --no-headers | grep -E "(apiserver|etcd|scheduler|controller)" || true
        exit 1
    fi
    
    echo -e "${RED}🔧 IP mismatch detected! Fixing configuration...${NC}"
    fix_kubelet_config "$CONTAINER_NAME" "$CONFIG_IP" "$CURRENT_IP"
    
    # Wait for node to become Ready
    if wait_for_node_ready "$CONTROL_PLANE_NODE"; then
        echo -e "${GREEN}🎉 Control plane IP fix completed successfully!${NC}"
        echo -e "${BLUE}📊 Final cluster status:${NC}"
        kubectl get nodes
    else
        echo -e "${RED}❌ Control plane node is still not Ready. Manual intervention may be required.${NC}"
        exit 1
    fi
}

# Handle script interruption
trap 'echo -e "\n${RED}❌ Script interrupted${NC}"; exit 1' INT TERM

# Run main function
main "$@"