#!/bin/bash

# Script to validate EKS cluster and Karpenter installation
# Run this after terraform apply completes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}==== $1 ====${NC}"
}

# Get cluster name from Terraform output
get_cluster_info() {
    print_info "Retrieving cluster information from Terraform..."
    
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "opsfleet-eks")
    AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
    
    print_info "Cluster Name: $CLUSTER_NAME"
    print_info "Region: $AWS_REGION"
}

# Update kubeconfig
update_kubeconfig() {
    print_info "Updating kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    print_info "kubeconfig updated"
}

# Check cluster access
check_cluster_access() {
    print_header "Checking Cluster Access"
    
    if kubectl cluster-info &> /dev/null; then
        print_info "Successfully connected to cluster"
        kubectl cluster-info
    else
        print_error "Cannot connect to cluster"
        exit 1
    fi
    echo
}

# Check nodes
check_nodes() {
    print_header "Checking Nodes"
    
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    print_info "Found $node_count node(s)"
    
    kubectl get nodes -o wide
    echo
}

# Check Karpenter installation
check_karpenter() {
    print_header "Checking Karpenter Installation"
    
    # Check Karpenter namespace
    if kubectl get namespace karpenter &> /dev/null; then
        print_info "Karpenter namespace exists"
    else
        print_error "Karpenter namespace not found"
        return 1
    fi
    
    # Check Karpenter pods
    print_info "Karpenter pods:"
    kubectl get pods -n karpenter
    echo
    
    # Check if pods are running
    local running_pods=$(kubectl get pods -n karpenter --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [ "$running_pods" -gt 0 ]; then
        print_info "Karpenter controller is running"
    else
        print_warning "Karpenter controller not running yet"
    fi
    echo
}

# Check NodePools
check_nodepools() {
    print_header "Checking Karpenter NodePools"
    
    if kubectl get nodepools &> /dev/null; then
        local nodepool_count=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l)
        print_info "Found $nodepool_count NodePool(s)"
        kubectl get nodepools
        echo
        
        # Show details of each NodePool
        for pool in $(kubectl get nodepools -o name 2>/dev/null); do
            print_info "Details for $pool:"
            kubectl describe "$pool"
            echo
        done
    else
        print_warning "No NodePools found or CRD not ready"
    fi
}

# Check EC2NodeClasses
check_nodeclasses() {
    print_header "Checking EC2NodeClasses"
    
    if kubectl get ec2nodeclasses &> /dev/null; then
        local nodeclass_count=$(kubectl get ec2nodeclasses --no-headers 2>/dev/null | wc -l)
        print_info "Found $nodeclass_count EC2NodeClass(es)"
        kubectl get ec2nodeclasses
        echo
    else
        print_warning "No EC2NodeClasses found or CRD not ready"
    fi
}

# Check cluster add-ons
check_addons() {
    print_header "Checking Cluster Add-ons"
    
    print_info "CoreDNS:"
    kubectl get deployment coredns -n kube-system
    echo
    
    print_info "AWS Node (VPC CNI):"
    kubectl get daemonset aws-node -n kube-system
    echo
    
    print_info "kube-proxy:"
    kubectl get daemonset kube-proxy -n kube-system
    echo
    
    print_info "EBS CSI Driver:"
    kubectl get deployment ebs-csi-controller -n kube-system 2>/dev/null || print_warning "EBS CSI controller not found"
    echo
}

# Check system pods
check_system_pods() {
    print_header "Checking System Pods"
    
    kubectl get pods -n kube-system
    echo
    
    # Check for any pods not running
    local not_running=$(kubectl get pods -A --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    if [ "$not_running" -gt 0 ]; then
        print_warning "Found $not_running pod(s) not in Running state:"
        kubectl get pods -A --field-selector=status.phase!=Running
    else
        print_info "All pods are running"
    fi
    echo
}

# Test Karpenter provisioning
test_karpenter_provisioning() {
    print_header "Testing Karpenter Provisioning (Optional)"
    
    read -p "Would you like to test Karpenter by creating a test pod? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    print_info "Creating test pod that requires x86 node..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: karpenter-test-x86
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
  containers:
  - name: pause
    image: k8s.gcr.io/pause:3.9
    resources:
      requests:
        cpu: "1"
        memory: "1Gi"
EOF
    
    print_info "Waiting for pod to be scheduled (max 2 minutes)..."
    kubectl wait --for=condition=Ready pod/karpenter-test-x86 --timeout=120s || true
    
    print_info "Pod status:"
    kubectl get pod karpenter-test-x86 -o wide
    echo
    
    print_info "Node provisioned by Karpenter:"
    local node_name=$(kubectl get pod karpenter-test-x86 -o jsonpath='{.spec.nodeName}')
    if [ -n "$node_name" ]; then
        kubectl get node "$node_name" -o wide
    fi
    echo
    
    read -p "Delete test pod? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete pod karpenter-test-x86
        print_info "Test pod deleted"
    fi
    echo
}

# Display summary
display_summary() {
    print_header "Validation Summary"
    
    print_info "Cluster validation complete!"
    echo
    print_info "Quick reference commands:"
    echo "  - View nodes: kubectl get nodes"
    echo "  - View Karpenter logs: kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f"
    echo "  - View NodePools: kubectl get nodepools"
    echo "  - View EC2NodeClasses: kubectl get ec2nodeclasses"
    echo "  - Deploy example app: kubectl apply -f examples/x86-deployment.yaml"
    echo
    print_info "Check examples/ directory for sample deployments"
}

# Main execution
main() {
    print_info "Starting cluster validation..."
    echo
    
    get_cluster_info
    echo
    
    update_kubeconfig
    echo
    
    check_cluster_access
    check_nodes
    check_karpenter
    check_nodepools
    check_nodeclasses
    check_addons
    check_system_pods
    
    test_karpenter_provisioning
    
    display_summary
}

# Run main
main
