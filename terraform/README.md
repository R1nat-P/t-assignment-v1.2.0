# EKS Cluster with Karpenter - Complete Documentation

This repository contains infrastructure as code (Terraform) for deploying a production-ready Amazon EKS cluster with Karpenter autoscaling, supporting both x86 and ARM64 (Graviton) instances.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Using the Cluster](#using-the-cluster)
- [IP Capacity Management](#ip-capacity-management)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Design Decisions](#design-decisions)
- [Cleanup](#cleanup)

---

## Overview

### What This Provides

- **EKS Cluster**: Kubernetes 1.35 (latest) with managed control plane
- **Karpenter Autoscaling**: Intelligent node provisioning for both x86 and ARM64
- **Graviton Support**: ARM64-based instances for 40% better price/performance
- **Spot Instances**: Up to 90% cost savings for fault-tolerant workloads
- **Production Ready**: VPC, security groups, IAM roles, and necessary add-ons

### Infrastructure Components

1. **Networking Layer**
   - Dedicated VPC (10.0.0.0/16)
   - 3 public + 3 private subnets across 3 AZs
   - 3 NAT Gateways for high availability

2. **EKS Control Plane**
   - Kubernetes 1.35
   - Public and private API endpoints
   - IRSA enabled for pod-level IAM

3. **Compute Layer**
   - Initial managed node group (2x t3.medium) for system workloads
   - Karpenter-managed nodes for applications
   - Support for x86_64 and ARM64 architectures

4. **Karpenter NodePools**
   - **x86-general-purpose**: c, m, r instance families (gen 5+)
   - **arm64-graviton**: c, m, r, t families (gen 6+, Graviton2/3)
   - Both support Spot and On-Demand instances

### Repository Structure

```
tech-assignment-v1.2.0/
├── README.md                    (this file)
└── terraform/
    ├── backend.tf               # S3 backend configuration
    ├── providers.tf             # AWS, Helm, kubectl providers
    ├── variables.tf             # Input variables
    ├── main.tf                  # Main configuration
    ├── vpc.tf                   # VPC and networking
    ├── eks.tf                   # EKS cluster
    ├── addons.tf                # EKS add-ons (CoreDNS, VPC CNI, etc.)
    ├── karpenter.tf             # Karpenter + NodePools
    ├── outputs.tf               # Output values
    ├── .gitignore               # Git ignore rules
    ├── terraform.tfvars.example # Example variables
    ├── examples/                # Kubernetes deployment examples
    │   ├── x86-deployment.yaml
    │   ├── arm64-deployment.yaml
    │   ├── spot-instance-deployment.yaml
    │   ├── on-demand-deployment.yaml
    │   └── mixed-architecture-deployment.yaml
    └── scripts/
        ├── setup.sh             # Setup and validation
        └── validate-cluster.sh  # Cluster validation
```

---

## Quick Start

### Prerequisites Checklist

- [ ] AWS CLI installed (`aws --version`)
- [ ] Terraform >= 1.6 (`terraform version`)
- [ ] kubectl installed (`kubectl version --client`)
- [ ] AWS credentials configured (`aws sts get-caller-identity`)
- [ ] S3 bucket for state storage

### 5-Minute Deploy

```bash
# 1. Create S3 bucket for Terraform state
aws s3 mb s3://opsfleet-terraform-v1.2.0
aws s3api put-bucket-versioning --bucket opsfleet-terraform-v1.2.0 \
  --versioning-configuration Status=Enabled

# 2. Navigate to terraform directory
cd terraform

# 3. Run setup script
./scripts/setup.sh

# 4. Deploy infrastructure (15-20 minutes)
terraform apply

# 5. Configure kubectl
aws eks update-kubeconfig --name opsfleet-eks --region us-east-1 --profile default

# 6. Verify
kubectl get nodes
kubectl get pods -A

# 7. Test with example
kubectl apply -f examples/x86-deployment.yaml
```

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Region (us-east-1)                   │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              VPC (10.0.0.0/16)                         │ │
│  │                                                        │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │ │
│  │  │   AZ-1   │  │   AZ-2   │  │   AZ-3   │            │ │
│  │  │  Public  │  │  Public  │  │  Public  │            │ │
│  │  │  Subnet  │  │  Subnet  │  │  Subnet  │            │ │
│  │  │  + NAT   │  │  + NAT   │  │  + NAT   │            │ │
│  │  ├──────────┤  ├──────────┤  ├──────────┤            │ │
│  │  │ Private  │  │ Private  │  │ Private  │            │ │
│  │  │ Subnet   │  │ Subnet   │  │ Subnet   │            │ │
│  │  │ EKS Nodes│  │ EKS Nodes│  │ EKS Nodes│            │ │
│  │  └──────────┘  └──────────┘  └──────────┘            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           EKS Control Plane (Managed by AWS)           │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

Node Types:
┌─────────────────────────────────┐
│ Initial Managed Node Group      │
│ - 2x t3.medium (x86)            │
│ - System components + Karpenter │
│ - Tainted: CriticalAddonsOnly   │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ Karpenter-Managed Nodes         │
│ x86:   c5, m5, r5, c6i, m6i     │
│ ARM64: t4g, m6g, c6g, m7g       │
│ Both: Spot + On-Demand          │
└─────────────────────────────────┘
```

### Component Details

**VPC Configuration:**
- CIDR: 10.0.0.0/16
- Private subnets: /20 each (4,096 IPs)
- Public subnets: /24 each (256 IPs)
- NAT Gateways: One per AZ (high availability)

**EKS Add-ons:**
- CoreDNS: v1.11.3-eksbuild.2
- kube-proxy: v1.31.2-eksbuild.3
- VPC CNI: v1.19.0-eksbuild.1 (with prefix delegation)
- EBS CSI Driver: v1.37.0-eksbuild.1

**Karpenter Configuration:**
- Version: 0.35.0
- Namespace: karpenter
- Consolidation: Enabled (WhenUnderutilized)
- Node expiry: 30 days

---

## Prerequisites

### Required Tools

1. **AWS CLI**
   ```bash
   # macOS
   brew install awscli
   
   # Verify
   aws --version
   aws configure  # Set up credentials
   ```

2. **Terraform >= 1.6**
   ```bash
   # macOS
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   
   # Verify
   terraform version
   ```

3. **kubectl**
   ```bash
   # macOS
   brew install kubectl
   
   # Verify
   kubectl version --client
   ```

4. **Helm** (optional, for debugging)
   ```bash
   # macOS
   brew install helm
   
   # Verify
   helm version
   ```

### AWS Permissions Required

Your AWS credentials need permissions for:
- VPC (create, modify)
- EKS (create, update clusters)
- EC2 (create instances, security groups)
- IAM (create roles, policies)
- S3 (read/write to state bucket)
- CloudWatch (logging)

### S3 Bucket Setup

```bash
# Create bucket for Terraform state
aws s3 mb s3://opsfleet-terraform-v1.2.0

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket opsfleet-terraform-v1.2.0 \
  --versioning-configuration Status=Enabled

# Enable encryption (recommended)
aws s3api put-bucket-encryption \
  --bucket opsfleet-terraform-v1.2.0 \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Verify
aws s3 ls s3://opsfleet-terraform-v1.2.0
```

---

## Configuration

### AWS Profile Configuration

The default AWS profile is `default`. To use a different profile:

**1. Update variables.tf:**
```hcl
variable "aws_profile" {
  default = "your-profile-name"  # Change from "default"
}
```

**2. Update backend.tf:**
```hcl
terraform {
  backend "s3" {
    profile = "your-profile-name"  # Change from "default"
    # ... other settings
  }
}
```

**3. Providers automatically use the variable**

### Region Configuration

Default region is `us-east-1`. To change:

**In variables.tf:**
```hcl
variable "aws_region" {
  default = "us-west-2"  # Change from "us-east-1"
}
```

**In backend.tf** (if S3 bucket is in different region):
```hcl
terraform {
  backend "s3" {
    region = "us-west-2"  # Match bucket region
    # ... other settings
  }
}
```

### Customizable Variables

Key variables in `variables.tf`:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | us-east-1 |
| `aws_profile` | AWS CLI profile | default |
| `cluster_name` | EKS cluster name | opsfleet-eks |
| `cluster_version` | Kubernetes version | 1.35 |
| `vpc_cidr` | VPC CIDR block | 10.0.0.0/16 |
| `environment` | Environment name | dev |
| `karpenter_version` | Karpenter version | 0.35.0 |

### Add-on Versions

Explicit versions in `variables.tf`:

```hcl
addon_version_coredns    = "v1.11.3-eksbuild.2"
addon_version_kube_proxy = "v1.31.2-eksbuild.3"
addon_version_vpc_cni    = "v1.19.0-eksbuild.1"
addon_version_ebs_csi    = "v1.37.0-eksbuild.1"
```

To find latest versions:
```bash
aws eks describe-addon-versions --addon-name coredns \
  --query 'addons[0].addonVersions[0].addonVersion'
```

---

## Deployment

### Step 1: Setup and Initialize

```bash
# Navigate to terraform directory
cd terraform

# Run automated setup script
./scripts/setup.sh
```

The setup script:
- Validates prerequisites (AWS CLI, Terraform, kubectl)
- Checks AWS credentials
- Verifies S3 bucket exists (or prompts to create)
- Initializes Terraform
- Validates configuration

### Step 2: Review Plan

```bash
terraform plan
```

Expected output:
- ~70-80 resources to be created
- VPC, subnets, route tables
- EKS cluster and node groups
- IAM roles and policies
- Security groups
- Karpenter installation

### Step 3: Apply Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment timeline:**
- 0-5 min: VPC and networking
- 5-15 min: EKS control plane
- 15-18 min: Initial node group
- 18-20 min: Karpenter installation
- **Total: 15-20 minutes**

### Step 4: Configure kubectl

```bash
# Command provided in Terraform outputs
aws eks update-kubeconfig \
  --name opsfleet-eks \
  --region us-east-1 \
  --profile default

# Verify connectivity
kubectl cluster-info
kubectl get nodes
```

### Step 5: Validate Installation

```bash
# Run validation script
./scripts/validate-cluster.sh
```

The script checks:
- Cluster connectivity
- Node availability
- Karpenter installation
- NodePools configuration
- System component health
- Optionally tests node provisioning

### Post-Deployment Verification

```bash
# Check nodes
kubectl get nodes -o wide

# Check Karpenter
kubectl get pods -n karpenter
kubectl get nodepools
kubectl get ec2nodeclasses

# Check system pods
kubectl get pods -n kube-system

# View outputs
terraform output
```

---

## Using the Cluster

### Deploying on x86 Instances

**Method 1: Using nodeSelector**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: x86-app
spec:
  nodeSelector:
    kubernetes.io/arch: amd64  # Request x86
  containers:
  - name: nginx
    image: nginx:latest
    resources:
      requests:
        cpu: "1"
        memory: "1Gi"
```

**Deploy:**
```bash
kubectl apply -f examples/x86-deployment.yaml

# Watch Karpenter provision node
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
kubectl get nodes --watch
```

### Deploying on ARM64 (Graviton) Instances

**Method 1: Using nodeSelector**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: graviton-app
spec:
  nodeSelector:
    kubernetes.io/arch: arm64  # Request Graviton
  containers:
  - name: nginx
    image: nginx:latest  # Must support ARM64
    resources:
      requests:
        cpu: "1"
        memory: "1Gi"
```

**Deploy:**
```bash
kubectl apply -f examples/arm64-deployment.yaml

# Verify node architecture
kubectl get nodes -L kubernetes.io/arch
```

**Important:** Ensure container images support ARM64 (most popular images do).

### Using Spot Instances

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: spot-app
spec:
  nodeSelector:
    karpenter.sh/capacity-type: spot  # Request Spot
    kubernetes.io/arch: arm64
  containers:
  - name: nginx
    image: nginx:latest
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
```

**Deploy:**
```bash
kubectl apply -f examples/spot-instance-deployment.yaml

# Verify capacity type
kubectl get nodes -L karpenter.sh/capacity-type
```

### Using On-Demand Instances

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-app
spec:
  nodeSelector:
    karpenter.sh/capacity-type: on-demand  # Request On-Demand
    kubernetes.io/arch: amd64
  containers:
  - name: app
    image: nginx:latest
```

### Monitoring Karpenter

**View logs:**
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

**Check NodePools:**
```bash
kubectl get nodepools
kubectl describe nodepool x86-general-purpose
kubectl describe nodepool arm64-graviton
```

**View provisioned nodes:**
```bash
kubectl get nodes -L \
  karpenter.sh/capacity-type,\
  kubernetes.io/arch,\
  node.kubernetes.io/instance-type
```

**Check node utilization:**
```bash
kubectl top nodes
kubectl top pods -A
```

---

## IP Capacity Management

### Overview

The cluster is configured to **prevent IP address exhaustion** with multiple safeguards:

### Current IP Capacity

**VPC Configuration:**
- **VPC CIDR**: 10.0.0.0/16 (65,536 total IPs)
- **Private Subnets**: 3 subnets × /20 (4,096 IPs each)
- **Usable IPs**: ~12,273 (after AWS reserves 5 IPs per subnet)

**Capacity with Prefix Delegation:**
- **Nodes Supported**: 100+ nodes comfortably
- **Pods per Node**: 50+ (vs 17-29 without prefix delegation)
- **Total Pod Capacity**: 5,000+ pods

### Safeguards in Place

#### 1. VPC CNI Prefix Delegation (Enabled)

Instead of allocating individual IPs to pods, each node gets a `/28` prefix (16 IPs):

```hcl
ENABLE_PREFIX_DELEGATION = "true"
WARM_PREFIX_TARGET       = "1"
```

**Benefits:**
- 3-4× more pods per node
- More efficient IP usage
- Significantly reduces IP exhaustion risk

#### 2. Automatic Capacity Validation

The `ip-capacity.tf` file automatically:
- ✅ Calculates total available IPs
- ✅ Validates sufficient capacity before deployment
- ✅ **Fails deployment** if IPs are insufficient
- ✅ Displays capacity summary during `terraform apply`

**Example output:**
```
IP Address Capacity Summary
================================================
VPC CIDR: 10.0.0.0/16
Total VPC IPs: 65536
Private Subnets: 3 x /20
Total usable private IPs: 12273

Configuration:
- VPC CNI Prefix Delegation: ENABLED
- Estimated pods/node: 50

Capacity Status: ✓ SUFFICIENT
================================================
```

#### 3. VPC CIDR Validation

The VPC CIDR is validated to ensure it's at least a `/16`:

```hcl
variable "vpc_cidr" {
  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "VPC CIDR must be at least a /16 to ensure sufficient IP capacity"
  }
}
```

### Monitoring IP Usage

**Check pod capacity per node:**
```bash
kubectl get nodes -o json | jq '.items[] | {
  name: .metadata.name,
  allocatable_pods: .status.allocatable.pods,
  capacity_pods: .status.capacity.pods
}'
```

**Monitor total pods:**
```bash
kubectl get pods -A | wc -l
```

**Check VPC CNI status:**
```bash
kubectl describe daemonset aws-node -n kube-system
```

**View IP usage:**
```bash
kubectl top nodes
```

**Get detailed IP information:**
```bash
terraform output ip_capacity_info
```

### Capacity Planning Table

| Metric | Value | Notes |
|--------|-------|-------|
| Total VPC IPs | 65,536 | 10.0.0.0/16 |
| Usable Private IPs | ~12,000 | After AWS reserves |
| Estimated Max Nodes | 100+ | Conservative estimate |
| Pods per Node | 50+ | With prefix delegation |
| Total Pod Capacity | 5,000+ | Theoretical maximum |
| Prefix Size | /28 | 16 IPs per prefix |

### If You Need More Capacity

**Option 1: Secondary CIDR Block** (recommended for growth)
```hcl
# Add to vpc.tf
module "vpc" {
  # ... existing config ...
  secondary_cidr_blocks = ["100.64.0.0/16"]
}
```

**Option 2: Larger Primary CIDR** (before initial deployment)
```hcl
# In variables.tf or terraform.tfvars
vpc_cidr = "10.0.0.0/8"  # 16 million IPs
```

**Option 3: Multiple Clusters**
For very large deployments, consider multiple smaller clusters instead of one massive cluster.

### IP Exhaustion Prevention Checklist

- [x] VPC CIDR validation (minimum /16)
- [x] Prefix delegation enabled
- [x] Automatic capacity calculation
- [x] Deployment fails if capacity insufficient
- [x] Clear capacity reporting
- [x] Monitoring commands provided
- [x] Private subnets properly sized (/20 each)

### Why You Won't Run Out of IPs

1. **Large VPC**: 65,536 IPs total
2. **Efficient Usage**: Prefix delegation reduces waste
3. **Validation**: Automatic checks before deployment
4. **Monitoring**: Easy to track usage
5. **Safety Factor**: Configured for 2× expected capacity

**With this configuration, IP exhaustion is highly unlikely.** The combination of a /16 VPC CIDR and prefix delegation provides enough capacity for most production workloads.

---

## Examples

All examples are in `terraform/examples/`:

### 1. x86 Deployment

Creates 3 nginx replicas on x86 instances with LoadBalancer service.

```bash
kubectl apply -f examples/x86-deployment.yaml
kubectl get pods -l arch=x86 -o wide
kubectl get svc x86-nginx-service
```

### 2. ARM64 Deployment

Creates 3 nginx replicas on Graviton instances with LoadBalancer service.

```bash
kubectl apply -f examples/arm64-deployment.yaml
kubectl get pods -l arch=arm64 -o wide
kubectl get svc arm64-nginx-service
```

### 3. Spot Instance Deployment

Cost-optimized deployment using Spot instances.

```bash
kubectl apply -f examples/spot-instance-deployment.yaml
kubectl get pods -l app=cost-optimized-app -o wide
```

### 4. On-Demand Deployment

Critical workload on reliable On-Demand instances.

```bash
kubectl apply -f examples/on-demand-deployment.yaml
kubectl get pods -l app=critical-app -o wide
```

### 5. Mixed Architecture

Single service load-balancing across both x86 and ARM64.

```bash
kubectl apply -f examples/mixed-architecture-deployment.yaml
kubectl get pods -l app=multi-arch-app -o wide
kubectl get svc multi-arch-service
```

### Clean Up Examples

```bash
# Delete all examples
kubectl delete -f examples/

# Wait for Karpenter to remove nodes
kubectl get nodes --watch
```

---

## Troubleshooting

### Common Issues

#### 1. S3 Bucket Does Not Exist

**Error:** `Failed to get existing workspaces: S3 bucket does not exist`

**Solution:**
```bash
aws s3 mb s3://opsfleet-terraform-v1.2.0
terraform init
```

#### 2. Cannot Connect to Cluster

**Error:** `Unable to connect to the server`

**Solution:**
```bash
aws eks update-kubeconfig \
  --name opsfleet-eks \
  --region us-east-1 \
  --profile default
```

#### 3. Pods Stuck in Pending

**Check pod events:**
```bash
kubectl describe pod <pod-name>
```

**Common causes:**
- Missing nodeSelector
- Insufficient resource requests
- NodePool limits exceeded
- Image not available for architecture

**Solution:**
```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Verify NodePools
kubectl get nodepools
kubectl describe nodepool x86-general-purpose
```

#### 4. Karpenter Not Provisioning Nodes

**Check:**
```bash
# Verify Karpenter is running
kubectl get pods -n karpenter

# Check logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Verify NodePools exist
kubectl get nodepools
kubectl get ec2nodeclasses

# Check IAM permissions
kubectl describe sa karpenter -n karpenter
```

#### 5. Node Not Ready

**Check:**
```bash
kubectl describe node <node-name>
kubectl get events --field-selector involvedObject.name=<node-name>
```

#### 6. Terraform State Locked

**Error:** `Error acquiring the state lock`

**Solution:**
```bash
# Wait for lock to clear, or force unlock (use with caution)
terraform force-unlock <lock-id>
```

### Debugging Commands

```bash
# Cluster info
kubectl cluster-info
kubectl get componentstatuses

# All resources
kubectl get all -A

# Events
kubectl get events -A --sort-by='.lastTimestamp'

# Node details
kubectl get nodes -o wide
kubectl describe node <node-name>

# Karpenter debug
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Pod details
kubectl get pods -A -o wide
kubectl describe pod <pod-name> -n <namespace>

# Check add-ons
kubectl get deployment -n kube-system
kubectl get daemonset -n kube-system
```

---

## Design Decisions

### Why Separate NodePools for x86 and ARM64?

**Rationale:**
- Clearer separation of concerns
- Easier to set different limits and policies
- Better visibility and monitoring
- Simpler troubleshooting
- Architecture-specific optimizations

### Why Initial Managed Node Group?

**Rationale:**
- Karpenter needs somewhere to run
- Guaranteed capacity for system components
- Prevents chicken-and-egg scenarios
- Bootstrapping requirement
- AWS best practice

**Configuration:**
- Size: 2x t3.medium (minimal but redundant)
- Taint: `CriticalAddonsOnly=true:NoSchedule`
- Prevents application workloads
- Forces use of Karpenter nodes

### Why Multiple NAT Gateways?

**Rationale:**
- High availability (no single point of failure)
- Better performance (distributed traffic)
- AWS production best practice
- Cost justified for reliability

**Cost vs. Benefit:**
- Cost: ~$100/month for 3 NAT Gateways
- Benefit: No downtime if one AZ fails
- Alternative: Single NAT (save $65/month, lose HA)

### Why Spot Instance Support?

**Rationale:**
- Up to 90% cost savings
- Karpenter handles interruptions gracefully
- Suitable for fault-tolerant workloads
- Diversification improves availability
- No forced choice - workload-dependent

### Why IRSA (IAM Roles for Service Accounts)?

**Rationale:**
- Pod-level IAM permissions (not node-level)
- Security best practice
- Principle of least privilege
- No AWS credentials in pods
- Required for many AWS integrations

### Why Prefix Delegation for VPC CNI?

**Rationale:**
- More IPs per node
- Fewer nodes needed
- Better pod density
- Cost optimization
- Supports larger clusters

### Why IMDSv2 Required?

**Rationale:**
- Security best practice
- Prevents SSRF attacks
- AWS recommendation
- Modern SDKs support it
- No significant drawbacks

---

## Cleanup

### Remove All Resources

```bash
# 1. Delete workloads
kubectl delete -f examples/

# 2. Wait for Karpenter to remove nodes
kubectl get nodes --watch
# Ctrl+C when only initial nodes remain

# 3. Destroy infrastructure
cd terraform
terraform destroy

# 4. Type 'yes' when prompted
```

**What gets deleted:**
- All Karpenter-provisioned nodes
- Initial node group
- EKS cluster
- VPC and networking
- IAM roles and policies
- Security groups
- All AWS resources created by Terraform

**What remains:**
- S3 bucket (manual deletion required)
- CloudWatch log groups (if any)

### Clean Up S3 Bucket (Optional)

```bash
# Empty the bucket
aws s3 rm s3://opsfleet-terraform-v1.2.0 --recursive

# Delete the bucket
aws s3 rb s3://opsfleet-terraform-v1.2.0
```

---

## Technical Reference

### Versions

- **Terraform**: >= 1.6
- **Kubernetes**: 1.35
- **Karpenter**: 0.35.0
- **AWS Provider**: ~> 5.0
- **Helm Provider**: ~> 2.12
- **kubectl Provider**: ~> 1.14

### Add-on Versions

- **CoreDNS**: v1.11.3-eksbuild.2
- **kube-proxy**: v1.31.2-eksbuild.3
- **VPC CNI**: v1.19.0-eksbuild.1
- **EBS CSI Driver**: v1.37.0-eksbuild.1

### Network Configuration

- **VPC CIDR**: 10.0.0.0/16
- **Private Subnets**: 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
- **Public Subnets**: 10.0.48.0/24, 10.0.49.0/24, 10.0.50.0/24

### NodePool Limits

- **Per NodePool**: 1000 vCPU, 1000Gi memory
- **Total Cluster**: 2000 vCPU, 2000Gi memory (configurable)

### Cost Estimates (us-east-1)

**Base Infrastructure:**
- EKS Control Plane: $72/month
- Initial Nodes (2x t3.medium): ~$60/month
- NAT Gateways (3): ~$100/month
- **Subtotal: ~$230/month**

**Variable Costs:**
- Karpenter nodes: Depends on workload
- Data transfer: Depends on usage

**Cost Optimization:**
- Spot instances: Up to 90% savings
- Graviton instances: Up to 40% better price/performance
- Single NAT Gateway for dev: Save $65/month

### Security Features

- Private subnets for all worker nodes
- Security groups with least-privilege access
- IMDSv2 required
- Encrypted EBS volumes
- IRSA for pod permissions
- VPC CNI with prefix delegation
- Cluster endpoint authentication

### Scaling Characteristics

**Initial State:**
- 2 initial nodes (t3.medium)
- Runs: Karpenter, CoreDNS, kube-proxy, VPC CNI, EBS CSI

**Application Scaling:**
- Pods trigger Karpenter provisioning
- 30-60 seconds to node ready
- Automatic instance type selection
- Spot when available

**Scale Down:**
- Automatic consolidation (30s underutilization)
- Graceful pod eviction
- Respects PodDisruptionBudgets
- Node expiry after 30 days

---

## Additional Resources

- **Karpenter Documentation**: https://karpenter.sh/
- **EKS Best Practices**: https://aws.github.io/aws-eks-best-practices/
- **AWS Graviton**: https://aws.amazon.com/ec2/graviton/
- **EKS Workshop**: https://www.eksworkshop.com/
- **Terraform AWS Modules**: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws

---

## License

This is a technical assignment solution provided as-is for evaluation purposes.

---

**Last Updated**: February 2026  
**Kubernetes Version**: 1.35  
**Karpenter Version**: 0.35.0
