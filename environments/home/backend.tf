terraform {
  backend "s3" {
    bucket         = "opentofu-state-home-iac-078129923125"
    key            = "home-iac/home/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "opentofu-state-locks-home-iac"
  }
}
