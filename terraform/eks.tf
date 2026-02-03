# EKS Cluster Module - Creates the Kubernetes control plane and managed node groups
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  # Cluster basic configuration
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Network configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster endpoint access configuration
  cluster_endpoint_public_access  = true # Allow public access (restrict in production)
  cluster_endpoint_private_access = true # Enable private endpoint for nodes

  # Enable IRSA (IAM Roles for Service Accounts) for pod-level IAM permissions
  enable_irsa = true

  # Cluster add-ons are now managed separately in addons.tf
  # This allows for better version control and management

  # Initial managed node group for system workloads and bootstrapping
  # Karpenter will handle most workload scaling
  eks_managed_node_groups = {
    # Initial node group for running Karpenter and system components
    initial = {
      name           = "initial-node-group"
      instance_types = ["t3.medium"] # Cost-effective instance for system workloads
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      # IAM role configuration
      iam_role_additional_policies = {
        # Required for EBS CSI driver
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }

      # Use AL2023 (Amazon Linux 2023) - AL2 support ends Nov 2025
      ami_type = "AL2023_x86_64_STANDARD"

      # Labels and taints
      labels = {
        role = "system"
      }

      # Taint to prefer Karpenter nodes for application workloads
      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      tags = {
        Name = "${var.cluster_name}-initial-node"
      }
    }
  }

  # Cluster access configuration
  # Allows current IAM identity to administer the cluster
  enable_cluster_creator_admin_permissions = true

  # Node security group rules
  node_security_group_additional_rules = {
    # Allow nodes to communicate with each other on all ports
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  tags = merge(
    local.tags,
    {
      # Karpenter uses this tag to discover the cluster
      "karpenter.sh/discovery" = var.cluster_name
    }
  )
}
