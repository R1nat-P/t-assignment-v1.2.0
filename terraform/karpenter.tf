# Karpenter Controller and Node Pools Configuration
# Karpenter is a Kubernetes autoscaler that provides just-in-time compute resources

# Configure Helm provider for Karpenter installation
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
    }
  }
}

# Configure kubectl provider for Karpenter custom resources
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
  }
}

# Configure Kubernetes provider for namespace creation
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
  }
}

# IAM role for Karpenter controller using IRSA
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Enable integration with EKS managed node groups
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["${var.karpenter_namespace}:karpenter"]

  # Create IAM role for nodes launched by Karpenter
  create_node_iam_role = true
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  tags = local.tags
}

# Install Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace        = var.karpenter_namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  # Wait for CRDs and webhook service to be ready before deploying node pools
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
        }
      }
      # Tolerations to run on initial node group
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]
      # Resource limits for Karpenter controller
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    })
  ]

  depends_on = [
    module.eks
  ]
}

# Wait for Karpenter webhook service to be fully ready
# The webhook service needs time to start even after Helm reports success
resource "time_sleep" "wait_for_karpenter" {
  depends_on = [
    helm_release.karpenter
  ]

  create_duration = "60s" # Wait 60 seconds for webhook to be ready
}

# Karpenter NodePool for x86_64 instances
# This NodePool will provision x86 instances for workloads
resource "kubectl_manifest" "karpenter_node_pool_x86" {
  depends_on = [
    time_sleep.wait_for_karpenter,
    aws_eks_addon.coredns
  ]

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "x86-general-purpose"
    }
    spec = {
      # Template for nodes created by this pool
      template = {
        metadata = {
          labels = {
            "workload-type" = "general"
            "arch"          = "amd64"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "x86-node-class"
          }
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"] # Allow both Spot and On-Demand
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r"] # Compute, memory, and general purpose
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["4"] # Use generation 5 and above (e.g., m5, c5, m6i)
            }
          ]
        }
      }
      # Limits for this NodePool
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      # Disruption settings - when to replace nodes
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized" # v1 API value
        consolidateAfter    = "1m"                       # Required in v1 - wait before consolidating
        budgets = [{
          nodes = "10%" # Allow disruption of up to 10% of nodes at a time
        }]
      }
    }
  })
}

# Karpenter NodeClass for x86_64 instances
# Defines AWS-specific configuration for x86 nodes
resource "kubectl_manifest" "karpenter_node_class_x86" {
  depends_on = [
    time_sleep.wait_for_karpenter,
    aws_eks_addon.coredns
  ]

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "x86-node-class"
    }
    spec = {
      # AMI selection - AL2 for Kubernetes 1.32
      amiSelectorTerms = [{
        alias = "al2023@latest" # Use latest AL2023 AMI
      }]

      amiFamily = "AL2023" # Amazon Linux 2023 (AL2 deprecated)

      # IAM role for nodes
      role = module.karpenter.node_iam_role_name

      # Subnet selection - use subnets tagged for Karpenter
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      # Security group selection
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      # User data for node initialization
      userData = <<-EOT
        #!/bin/bash
        echo "Running x86 node initialization"
      EOT

      # Tags to apply to EC2 instances
      tags = {
        Name         = "${var.cluster_name}-karpenter-x86"
        NodePool     = "x86-general-purpose"
        Architecture = "x86_64"
      }

      # Block device mappings for root volume
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "100Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]

      # Metadata options for IMDS
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required" # Require IMDSv2
      }
    }
  })
}

# Karpenter NodePool for ARM64 (Graviton) instances
# This NodePool will provision ARM-based Graviton instances
resource "kubectl_manifest" "karpenter_node_pool_arm" {
  depends_on = [
    time_sleep.wait_for_karpenter,
    aws_eks_addon.coredns
  ]

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "arm64-graviton"
    }
    spec = {
      # Template for nodes created by this pool
      template = {
        metadata = {
          labels = {
            "workload-type" = "general"
            "arch"          = "arm64"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "arm64-node-class"
          }
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"] # Allow both Spot and On-Demand
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r", "t"] # Graviton instance families
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["5"] # Graviton2 and Graviton3 (generation 6+)
            }
          ]
        }
      }
      # Limits for this NodePool
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      # Disruption settings
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized" # v1 API value
        consolidateAfter    = "1m"                       # Required in v1 - wait before consolidating
        budgets = [{
          nodes = "10%" # Allow disruption of up to 10% of nodes at a time
        }]
      }
    }
  })
}

# Karpenter NodeClass for ARM64 (Graviton) instances
# Defines AWS-specific configuration for Graviton nodes
resource "kubectl_manifest" "karpenter_node_class_arm" {
  depends_on = [
    time_sleep.wait_for_karpenter,
    aws_eks_addon.coredns
  ]

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "arm64-node-class"
    }
    spec = {
      # AMI selection - AL2 ARM64 for Kubernetes 1.32
      amiSelectorTerms = [{
        alias = "al2023@latest" # Use latest AL2023 ARM64 AMI
      }]

      amiFamily = "AL2023" # Amazon Linux 2023 (AL2 deprecated)

      # IAM role for nodes
      role = module.karpenter.node_iam_role_name

      # Subnet selection
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      # Security group selection
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      # User data for node initialization
      userData = <<-EOT
        #!/bin/bash
        echo "Running ARM64 Graviton node initialization"
      EOT

      # Tags to apply to EC2 instances
      tags = {
        Name         = "${var.cluster_name}-karpenter-arm64"
        NodePool     = "arm64-graviton"
        Architecture = "arm64"
      }

      # Block device mappings
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "100Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]

      # Metadata options for IMDS
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required" # Require IMDSv2
      }
    }
  })
}
