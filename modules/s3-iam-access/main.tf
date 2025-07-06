# S3 IAM Access Module
# Manages IAM roles and policies for S3 bucket access

variable "bucket_access_configs" {
  description = "Map of IAM access configurations for S3 buckets"
  type = map(object({
    bucket_name = string
    bucket_arn  = string
    
    # List of IAM roles that should have access
    role_access = list(object({
      role_name    = string
      role_arn     = string
      permissions  = list(string) # e.g., ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      prefix       = optional(string, "*") # Path prefix for access, defaults to entire bucket
    }))
    
    # Cross-account access
    cross_account_access = optional(list(object({
      account_id  = string
      external_id = optional(string)
      permissions = list(string)
      prefix      = optional(string, "*")
    })), [])
  }))
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Create bucket policies for role access
resource "aws_s3_bucket_policy" "role_access" {
  for_each = var.bucket_access_configs
  
  bucket = each.value.bucket_name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # Role-based access statements
      [for role in each.value.role_access : {
        Sid    = "AllowRole${replace(role.role_name, "-", "")}"
        Effect = "Allow"
        Principal = {
          AWS = role.role_arn
        }
        Action   = role.permissions
        Resource = role.prefix == "*" ? ["${each.value.bucket_arn}/*", each.value.bucket_arn] : ["${each.value.bucket_arn}/${role.prefix}/*"]
      }],
      
      # Cross-account access statements
      [for account in each.value.cross_account_access : {
        Sid    = "AllowCrossAccount${account.account_id}"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${account.account_id}:root"
        }
        Action   = account.permissions
        Resource = account.prefix == "*" ? ["${each.value.bucket_arn}/*", each.value.bucket_arn] : ["${each.value.bucket_arn}/${account.prefix}/*"]
        Condition = account.external_id != null ? {
          StringEquals = {
            "sts:ExternalId" = account.external_id
          }
        } : null
      }]
    )
  })
}

# Create IAM policies for each role (if they don't exist)
resource "aws_iam_policy" "bucket_access" {
  for_each = {
    for idx, config in flatten([
      for bucket_key, bucket in var.bucket_access_configs : [
        for role in bucket.role_access : {
          key         = "${bucket_key}-${role.role_name}"
          bucket_name = bucket.bucket_name
          bucket_arn  = bucket.bucket_arn
          role_name   = role.role_name
          permissions = role.permissions
          prefix      = role.prefix
        }
      ]
    ]) : config.key => config
  }
  
  name        = "s3-access-${each.value.bucket_name}-${each.value.role_name}"
  description = "S3 access policy for ${each.value.role_name} to ${each.value.bucket_name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = each.value.permissions
        Resource = each.value.prefix == "*" ? [
          "${each.value.bucket_arn}/*",
          each.value.bucket_arn
        ] : [
          "${each.value.bucket_arn}/${each.value.prefix}/*"
        ]
      }
    ]
  })
  
  tags = merge(
    var.common_tags,
    {
      Name       = "s3-access-${each.value.bucket_name}-${each.value.role_name}"
      BucketName = each.value.bucket_name
      RoleName   = each.value.role_name
    }
  )
}

# Attach policies to roles
resource "aws_iam_role_policy_attachment" "bucket_access" {
  for_each = {
    for idx, config in flatten([
      for bucket_key, bucket in var.bucket_access_configs : [
        for role in bucket.role_access : {
          key         = "${bucket_key}-${role.role_name}"
          role_name   = role.role_name
          policy_arn  = aws_iam_policy.bucket_access["${bucket_key}-${role.role_name}"].arn
        }
      ]
    ]) : config.key => config
  }
  
  role       = each.value.role_name
  policy_arn = each.value.policy_arn
}