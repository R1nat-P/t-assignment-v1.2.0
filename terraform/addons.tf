# EKS Cluster Add-ons Configuration
# This file manages all EKS cluster add-ons with explicit version control
# Each add-on version is independently specified, not tied to cluster version
#
# Current Add-on Versions (compatible with K8s 1.32):
# - CoreDNS:          v1.11.3-eksbuild.1
# - kube-proxy:       v1.32.0-eksbuild.2
# - VPC CNI:          v1.18.5-eksbuild.1
# - EBS CSI Driver:   v1.36.0-eksbuild.1
#
# To find latest versions, run:
# aws eks describe-addon-versions --addon-name <addon-name> --query 'addons[0].addonVersions[0].addonVersion'

# CoreDNS Add-on - DNS service for the cluster
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.addon_version_coredns
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    local.tags,
    {
      Name = "coredns"
    }
  )

  depends_on = [
    module.eks.eks_managed_node_groups
  ]
}

# kube-proxy Add-on - Network proxy that runs on each node
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = var.addon_version_kube_proxy
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    local.tags,
    {
      Name = "kube-proxy"
    }
  )

  depends_on = [
    module.eks.eks_managed_node_groups
  ]
}

# VPC CNI Add-on - Networking plugin for pod IP allocation
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_version_vpc_cni
  service_account_role_arn    = module.vpc_cni_irsa.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Configuration for VPC CNI with prefix delegation
  configuration_values = jsonencode({
    env = {
      # Enable prefix delegation for more IPs per node
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })

  tags = merge(
    local.tags,
    {
      Name = "vpc-cni"
    }
  )

  depends_on = [
    module.vpc_cni_irsa
  ]
}

# EBS CSI Driver Add-on - For persistent volume support
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_version_ebs_csi
  service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    local.tags,
    {
      Name = "aws-ebs-csi-driver"
    }
  )

  depends_on = [
    module.ebs_csi_irsa,
    module.eks.eks_managed_node_groups
  ]
}

# IAM role for VPC CNI plugin using IRSA
module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "VPC-CNI-IRSA-"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

# IAM role for EBS CSI driver using IRSA
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "EBS-CSI-IRSA-"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# Outputs for add-on versions
output "addon_versions" {
  description = "Installed EKS add-on versions"
  value = {
    coredns            = aws_eks_addon.coredns.addon_version
    kube_proxy         = aws_eks_addon.kube_proxy.addon_version
    vpc_cni            = aws_eks_addon.vpc_cni.addon_version
    aws_ebs_csi_driver = aws_eks_addon.ebs_csi.addon_version
  }
}
