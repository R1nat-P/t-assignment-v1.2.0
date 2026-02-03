# Backend configuration for storing Terraform state in S3
# The state will be stored in the S3 bucket: opsfleet-terraform-v1.2.0
terraform {
  backend "s3" {
    bucket = "opsfleet-terraform-v1.2.0"     # S3 bucket name for state storage
    key    = "eks-cluster/terraform.tfstate" # Path within the bucket
    region = "us-east-1"                     # AWS region where the bucket is located (change if needed)

    # Profile to use for AWS authentication (change if not using default)
    profile = "default"

    # Enable encryption for state file
    encrypt = true

    # Uncomment and configure if using DynamoDB for state locking
    # dynamodb_table = "terraform-state-lock"
  }
}
