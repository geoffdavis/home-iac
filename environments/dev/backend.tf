# Backend configuration for OpenTofu state management
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket" # Replace with your state bucket name
    key            = "home-iac/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock" # Optional: for state locking
  }
}