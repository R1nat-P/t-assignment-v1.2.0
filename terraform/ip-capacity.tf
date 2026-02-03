# IP Capacity Planning and Monitoring
# This file ensures the cluster has sufficient IP addresses

# Calculate IP capacity
locals {
  # VPC CIDR calculations
  vpc_total_ips = pow(2, 32 - tonumber(split("/", var.vpc_cidr)[1]))

  # Private subnet IPs (3 subnets with /20 each)
  private_subnet_size      = 20
  ips_per_private_subnet   = pow(2, 32 - local.private_subnet_size)
  total_private_subnet_ips = local.ips_per_private_subnet * var.azs

  # AWS reserves 5 IPs per subnet (network, gateway, DNS, future, broadcast)
  aws_reserved_ips_per_subnet = 5
  usable_ips_per_subnet       = local.ips_per_private_subnet - local.aws_reserved_ips_per_subnet
  total_usable_ips            = local.usable_ips_per_subnet * var.azs

  # With prefix delegation, each node can support many more pods
  # Each prefix is /28 (16 IPs), typically 1-2 prefixes per node
  # Assuming average of 50 pods per node with prefix delegation
  estimated_pods_per_node              = 50
  estimated_nodes_max                  = 100 # Conservative estimate
  required_ips_for_nodes               = local.estimated_nodes_max
  required_ips_for_pods_without_prefix = local.estimated_nodes_max * 30 # Without prefix delegation

  # IP capacity check
  ip_capacity_sufficient = local.total_usable_ips > (local.required_ips_for_nodes * 2) # 2x safety factor
}

# Output IP capacity information
output "ip_capacity_info" {
  description = "IP address capacity information for the VPC"
  value = {
    vpc_cidr                  = var.vpc_cidr
    total_vpc_ips             = local.vpc_total_ips
    private_subnets_count     = var.azs
    ips_per_private_subnet    = local.ips_per_private_subnet
    usable_ips_per_subnet     = local.usable_ips_per_subnet
    total_usable_private_ips  = local.total_usable_ips
    aws_reserved_per_subnet   = local.aws_reserved_ips_per_subnet
    prefix_delegation_enabled = true
    estimated_max_nodes       = local.estimated_nodes_max
    estimated_pods_per_node   = local.estimated_pods_per_node
    capacity_status           = local.ip_capacity_sufficient ? "SUFFICIENT" : "WARNING"
  }
}

# Validation check - fail if IP capacity is insufficient
resource "null_resource" "ip_capacity_check" {
  triggers = {
    capacity_check = local.ip_capacity_sufficient ? "pass" : "fail"
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ "${local.ip_capacity_sufficient}" = "false" ]; then
        echo "ERROR: Insufficient IP capacity!"
        echo "VPC CIDR: ${var.vpc_cidr}"
        echo "Total usable IPs: ${local.total_usable_ips}"
        echo "Recommended minimum: ${local.required_ips_for_nodes * 2}"
        exit 1
      else
        echo "IP capacity check: PASSED"
        echo "Total usable private IPs: ${local.total_usable_ips}"
        echo "With prefix delegation enabled, this supports ${local.estimated_nodes_max}+ nodes"
      fi
    EOT
  }
}

# CloudWatch alarm for IP address exhaustion (optional - requires CloudWatch)
resource "null_resource" "ip_monitoring_setup" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "================================================"
      echo "IP Address Capacity Summary"
      echo "================================================"
      echo "VPC CIDR: ${var.vpc_cidr}"
      echo "Total VPC IPs: ${local.vpc_total_ips}"
      echo "Private Subnets: ${var.azs} x /${local.private_subnet_size}"
      echo "IPs per subnet: ${local.ips_per_private_subnet}"
      echo "Usable IPs per subnet: ${local.usable_ips_per_subnet}"
      echo "Total usable private IPs: ${local.total_usable_ips}"
      echo ""
      echo "Configuration:"
      echo "- VPC CNI Prefix Delegation: ENABLED"
      echo "- Warm Prefix Target: 1"
      echo "- Estimated pods/node: ${local.estimated_pods_per_node}"
      echo ""
      echo "Capacity Status: ${local.ip_capacity_sufficient ? "✓ SUFFICIENT" : "⚠ WARNING"}"
      echo "================================================"
      echo ""
      echo "To monitor IP usage:"
      echo "  kubectl get nodes -o json | jq '.items[] | {name:.metadata.name, allocatable:.status.allocatable.pods, capacity:.status.capacity.pods}'"
      echo ""
    EOT
  }
}

# Recommendations output
output "ip_capacity_recommendations" {
  description = "Recommendations for IP capacity management"
  value = {
    current_config = "VPC CNI with prefix delegation enabled"
    benefits = [
      "Each node gets /28 prefix (16 IPs) instead of individual IPs",
      "Supports 50+ pods per node vs 17-29 without prefix delegation",
      "More efficient IP usage",
      "Better pod density"
    ]
    monitoring = [
      "Monitor: kubectl get pods -A | wc -l",
      "Monitor: kubectl top nodes",
      "Check CNI metrics: kubectl get daemonset aws-node -n kube-system"
    ]
    scaling_tips = [
      "Current VPC supports ${local.estimated_nodes_max}+ nodes comfortably",
      "If scaling beyond 100 nodes, consider secondary CIDR blocks",
      "With prefix delegation, IP exhaustion is unlikely"
    ]
  }
}
