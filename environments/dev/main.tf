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

# Configure UniFi provider
provider "unifi" {
  username       = var.unifi_username
  password       = var.unifi_password
  api_url        = var.unifi_api_url
  allow_insecure = var.unifi_allow_insecure
  site           = var.unifi_site
}

# Variables are defined in variables.tf

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
