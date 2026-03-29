# AWS provider — credentials sourced from environment via 1Password
provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    ManagedBy   = "OpenTofu"
    Environment = "home"
    Repository  = "home-iac"
  }
}
