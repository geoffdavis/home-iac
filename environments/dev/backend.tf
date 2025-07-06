# Backend configuration for OpenTofu state management
terraform {
  backend "s3" {
    bucket  = "opentofu-state-home-iac-078129923125"
    key     = "home-iac/dev/terraform.tfstate"
    region  = "us-west-2"
    encrypt = true
    # DynamoDB table for locking is optional and requires additional permissions
    dynamodb_table = "opentofu-state-locks-home-iac"
  }
}