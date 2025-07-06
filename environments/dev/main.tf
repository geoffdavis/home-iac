# OpenTofu (Terraform) configuration for AWS - dev environment

# Configure 1Password provider
provider "onepassword" {
  # Using your personal 1Password account
  account = "camiandgeoff.1password.com"
}

# Configure AWS provider
# The AWS credentials will be set via environment variables
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
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
# NOTE: Configuration loaded from s3-buckets.tf
