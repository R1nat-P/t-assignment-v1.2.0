# VPC Module - Creates a new VPC with public and private subnets
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # VPC basic configuration
  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  # Availability zones and subnet configuration
  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]      # 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)] # 10.0.48.0/24, 10.0.49.0/24, 10.0.50.0/24

  # Enable NAT gateway for private subnet internet access
  enable_nat_gateway   = true
  single_nat_gateway   = false # Use one NAT gateway per AZ for high availability
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Kubernetes and EKS specific tags for subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1" # Tag for public load balancers
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1" # Tag for internal load balancers
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Karpenter uses this tag to discover subnets for node placement
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}
