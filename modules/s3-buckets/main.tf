# S3 Buckets Module

variable "buckets" {
  description = "Map of S3 bucket configurations"
  type = map(object({
    bucket_name = string
    acl         = optional(string, "private")
    versioning  = optional(bool, false)
    lifecycle_rules = optional(list(object({
      id                         = string
      enabled                    = bool
      prefix                     = optional(string, "")
      expiration_days            = optional(number)
      noncurrent_expiration_days = optional(number)
    })), [])
    server_side_encryption = optional(object({
      algorithm          = string
      kms_master_key_id  = optional(string)
      bucket_key_enabled = optional(bool, false)
    }))
    public_access_block = optional(object({
      block_public_acls       = optional(bool, true)
      block_public_policy     = optional(bool, true)
      ignore_public_acls      = optional(bool, true)
      restrict_public_buckets = optional(bool, true)
    }))
    bucket_policy = optional(string)
    tags          = optional(map(string), {})
  }))
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# S3 Buckets
resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket = each.value.bucket_name

  tags = merge(
    var.common_tags,
    each.value.tags,
    {
      Name = each.value.bucket_name
    }
  )
}

# Bucket ACL (separate resource in AWS provider v4+)
resource "aws_s3_bucket_acl" "this" {
  for_each = { for k, v in var.buckets : k => v if v.acl != null }

  bucket = aws_s3_bucket.this[each.key].id
  acl    = each.value.acl
}

# Bucket Versioning
resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in var.buckets : k => v if v.versioning }

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = { for k, v in var.buckets : k => v if v.server_side_encryption != null }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = each.value.server_side_encryption.algorithm
      kms_master_key_id = each.value.server_side_encryption.kms_master_key_id
    }
    bucket_key_enabled = each.value.server_side_encryption.bucket_key_enabled
  }
}

# Public access block
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = { for k, v in var.buckets : k => v if v.public_access_block != null }

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = each.value.public_access_block.block_public_acls
  block_public_policy     = each.value.public_access_block.block_public_policy
  ignore_public_acls      = each.value.public_access_block.ignore_public_acls
  restrict_public_buckets = each.value.public_access_block.restrict_public_buckets
}

# Bucket lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for k, v in var.buckets : k => v if length(v.lifecycle_rules) > 0 }

  bucket = aws_s3_bucket.this[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_expiration_days
        }
      }
    }
  }
}

# Bucket policies
resource "aws_s3_bucket_policy" "this" {
  for_each = { for k, v in var.buckets : k => v if v.bucket_policy != null }

  bucket = aws_s3_bucket.this[each.key].id
  policy = each.value.bucket_policy
}