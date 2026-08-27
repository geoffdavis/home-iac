# AWS provider — credentials sourced from environment via 1Password.
# (No-op touch to force a real Digger plan run — see PR #36.)
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
