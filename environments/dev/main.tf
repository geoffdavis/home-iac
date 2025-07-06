# OpenTofu (Terraform) configuration for AWS - dev environment

# Configure 1Password provider
provider "onepassword" {
  # The provider will use OP_ACCOUNT environment variable or 1Password CLI config
}

# Data source to retrieve AWS credentials from 1Password
data "onepassword_item" "aws_credentials" {
  vault = "Private"
  title = "AWS Access Key - S3 - Personal"
}

# Configure AWS provider with credentials from 1Password
provider "aws" {
  region     = var.aws_region
  access_key = data.onepassword_item.aws_credentials.section[0].field[0].value
  secret_key = data.onepassword_item.aws_credentials.section[0].field[1].value
}

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Local values for common tags
locals {
  common_tags = {
    ManagedBy   = "OpenTofu"
    Environment = "dev"
    Repository  = "home-iac"
  }
}

# Import existing S3 buckets
# NOTE: Uncomment and configure after running discovery script
# module "s3_buckets" {
#   source = "../../modules/s3-buckets"
#   
#   buckets = {
#     # Will be populated with discovered buckets
#   }
#   
#   common_tags = local.common_tags
# }
