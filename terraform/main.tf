# Data source to get available availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

# Local values for common configurations
locals {
  # Use first N availability zones
  azs = slice(data.aws_availability_zones.available.names, 0, var.azs)

  # Account ID
  account_id = data.aws_caller_identity.current.account_id

  # Common tags to apply to all resources
  tags = {
    Environment = var.environment
    Project     = var.project_name
    Terraform   = "true"
  }
}
