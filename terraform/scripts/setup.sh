#!/bin/bash

# Setup script for EKS cluster with Karpenter
# This script helps with initial setup and validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    else
        print_info "AWS CLI: $(aws --version)"
    fi
    
    # Check for Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    else
        print_info "Terraform: $(terraform version | head -n1)"
    fi
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    else
        print_info "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi
    
    # Report missing tools
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and try again"
        exit 1
    fi
    
    print_info "All prerequisites are installed"
}

# Check AWS credentials
check_aws_credentials() {
    print_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured properly"
        print_error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    print_info "AWS Account ID: $account_id"
    print_info "AWS User/Role: $user_arn"
}

# Check if S3 bucket exists
check_s3_bucket() {
    local bucket_name="opsfleet-terraform-v1.2.0"
    print_info "Checking S3 bucket for Terraform state..."
    
    if ! aws s3 ls "s3://$bucket_name" &> /dev/null; then
        print_warning "S3 bucket '$bucket_name' does not exist"
        read -p "Would you like to create it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Creating S3 bucket..."
            aws s3 mb "s3://$bucket_name"
            
            # Enable versioning
            print_info "Enabling versioning on S3 bucket..."
            aws s3api put-bucket-versioning \
                --bucket "$bucket_name" \
                --versioning-configuration Status=Enabled
            
            print_info "S3 bucket created successfully"
        else
            print_error "S3 bucket is required for Terraform state. Exiting."
            exit 1
        fi
    else
        print_info "S3 bucket '$bucket_name' exists"
    fi
}

# Initialize Terraform
init_terraform() {
    print_info "Initializing Terraform..."
    terraform init
    print_info "Terraform initialized successfully"
}

# Validate Terraform configuration
validate_terraform() {
    print_info "Validating Terraform configuration..."
    terraform validate
    print_info "Terraform configuration is valid"
}

# Format Terraform files
format_terraform() {
    print_info "Formatting Terraform files..."
    terraform fmt -recursive
    print_info "Terraform files formatted"
}

# Main execution
main() {
    print_info "Starting EKS cluster setup validation..."
    echo
    
    # Run checks
    check_prerequisites
    echo
    
    check_aws_credentials
    echo
    
    check_s3_bucket
    echo
    
    init_terraform
    echo
    
    validate_terraform
    echo
    
    format_terraform
    echo
    
    print_info "Setup validation complete!"
    echo
    print_info "Next steps:"
    echo "  1. Review variables in variables.tf or create terraform.tfvars"
    echo "  2. Run 'terraform plan' to review changes"
    echo "  3. Run 'terraform apply' to create infrastructure"
    echo
}

# Run main function
main
