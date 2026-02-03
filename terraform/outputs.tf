# Output values to display after terraform apply

# EKS Cluster outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# VPC outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

# Karpenter outputs
output "karpenter_irsa_role_arn" {
  description = "ARN of IAM role for Karpenter controller"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_role_arn" {
  description = "ARN of IAM role for Karpenter nodes"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_node_role_name" {
  description = "Name of IAM role for Karpenter nodes"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_queue_name" {
  description = "Name of SQS queue for Karpenter interruption handling"
  value       = module.karpenter.queue_name
}

# Configuration command outputs
output "configure_kubectl" {
  description = "Command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region} --profile ${var.aws_profile}"
}

output "region" {
  description = "AWS region where resources are created"
  value       = var.aws_region
}
