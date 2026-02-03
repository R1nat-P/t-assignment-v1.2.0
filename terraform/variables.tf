# AWS Region where resources will be created
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# AWS CLI profile to use (change if not using 'default')
variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}

# Environment name (dev, staging, prod, etc.)
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Project name used for resource naming and tagging
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "opsfleet"
}

# EKS cluster name
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "opsfleet-eks"
}

# Kubernetes version for EKS cluster
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.32" # Stable version with broad compatibility
}

# VPC CIDR block
variable "vpc_cidr" {
  description = "CIDR block for VPC (minimum /16 recommended for EKS with prefix delegation)"
  type        = string
  default     = "10.0.0.0/16" # Provides 65,536 IPs

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "VPC CIDR must be valid and at least a /16 to ensure sufficient IP capacity for EKS."
  }
}

# Availability zones to use (will use first 3 AZs in the region)
variable "azs" {
  description = "Number of availability zones to use"
  type        = number
  default     = 3
}

# Karpenter namespace
variable "karpenter_namespace" {
  description = "Namespace for Karpenter controller"
  type        = string
  default     = "karpenter"
}

# Karpenter version
variable "karpenter_version" {
  description = "Version of Karpenter to install"
  type        = string
  default     = "1.0.7" # Latest stable version with K8s 1.32 support
}

# EKS Add-on versions - Explicit versions for each add-on
# These are independent of the cluster_version variable
# Update these versions as needed for your environment

variable "addon_version_coredns" {
  description = "Specific version of CoreDNS add-on"
  type        = string
  default     = "v1.11.3-eksbuild.1" # Compatible with K8s 1.32
}

variable "addon_version_kube_proxy" {
  description = "Specific version of kube-proxy add-on"
  type        = string
  default     = "v1.32.0-eksbuild.2" # Compatible with K8s 1.32
}

variable "addon_version_vpc_cni" {
  description = "Specific version of VPC CNI add-on"
  type        = string
  default     = "v1.18.5-eksbuild.1" # Compatible with K8s 1.32
}

variable "addon_version_ebs_csi" {
  description = "Specific version of EBS CSI driver add-on"
  type        = string
  default     = "v1.36.0-eksbuild.1" # Compatible with K8s 1.32
}
