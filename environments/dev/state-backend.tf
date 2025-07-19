# S3 Backend Infrastructure for OpenTofu State
# This file creates the S3 bucket and DynamoDB table for state management

resource "aws_s3_bucket" "terraform_state" {
  bucket = "opentofu-state-home-iac-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name     = "OpenTofu State Storage"
      Purpose  = "terraform-state"
      Critical = "true"
    }
  )
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking (requires additional IAM permissions)
# Uncomment if you have DynamoDB permissions:
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "opentofu-state-locks-home-iac"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(
    local.common_tags,
    {
      Name     = "OpenTofu State Locks"
      Purpose  = "terraform-state-locking"
      Critical = "true"
    }
  )
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Output the backend configuration
output "backend_config" {
  description = "Backend configuration for terraform block"
  value = {
    bucket = aws_s3_bucket.terraform_state.id
    key    = "home-iac/dev/terraform.tfstate"
    region = var.aws_region
    # dynamodb_table = aws_dynamodb_table.terraform_locks.name
    encrypt = true
  }
}