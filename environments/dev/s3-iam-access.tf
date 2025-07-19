# IAM Access Configuration for S3 Buckets
# Configures IAM policies and access for applications

# Create IAM user for Longhorn backups
resource "aws_iam_user" "longhorn_backup" {
  name = "longhorn-backup-user"
  path = "/system/"

  tags = merge(
    local.common_tags,
    {
      Name        = "longhorn-backup-user"
      Application = "longhorn"
      Purpose     = "s3-backup-access"
    }
  )
}

# Create access key for Longhorn user
resource "aws_iam_access_key" "longhorn_backup" {
  user = aws_iam_user.longhorn_backup.name
}

# IAM policy for Longhorn S3 backup access
resource "aws_iam_policy" "longhorn_backup_s3_access" {
  name        = "longhorn-backup-s3-access"
  path        = "/"
  description = "IAM policy for Longhorn to access S3 backup bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = module.s3_buckets.bucket_arns["longhorn_backups_home_ops"]
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${module.s3_buckets.bucket_arns["longhorn_backups_home_ops"]}/*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "longhorn-backup-s3-access"
      Application = "longhorn"
    }
  )
}

# Attach the policy to the Longhorn user
resource "aws_iam_user_policy_attachment" "longhorn_backup_s3_access" {
  user       = aws_iam_user.longhorn_backup.name
  policy_arn = aws_iam_policy.longhorn_backup_s3_access.arn
}

# Create IAM user for PostgreSQL backups
resource "aws_iam_user" "postgresql_backup" {
  name = "postgresql-backup-user"
  path = "/system/"

  tags = merge(
    local.common_tags,
    {
      Name        = "postgresql-backup-user"
      Application = "postgresql"
      Purpose     = "s3-backup-access"
    }
  )
}

# Create access key for PostgreSQL user
resource "aws_iam_access_key" "postgresql_backup" {
  user = aws_iam_user.postgresql_backup.name

  # Force regeneration of credentials by updating this timestamp
  # Update this value whenever credentials need to be rotated
  lifecycle {
    create_before_destroy = true
  }

  # Keepers to force regeneration when needed
  # Change the rotation_trigger value to force new credentials
  depends_on = [time_rotating.postgresql_backup_rotation]
}

# Time-based rotation trigger for PostgreSQL backup credentials
resource "time_rotating" "postgresql_backup_rotation" {
  # Rotate credentials immediately by setting a past date
  # This forces regeneration on the next apply
  rotation_rfc3339 = "2025-07-19T16:25:00Z"

  # Optional: Set up automatic rotation (uncomment if desired)
  # rotation_days = 90
}

# IAM policy for PostgreSQL S3 backup access
resource "aws_iam_policy" "postgresql_backup_s3_access" {
  name        = "postgresql-backup-s3-access"
  path        = "/"
  description = "IAM policy for PostgreSQL to access S3 backup bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = module.s3_buckets.bucket_arns["postgresql_backup_home_ops"]
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${module.s3_buckets.bucket_arns["postgresql_backup_home_ops"]}/*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "postgresql-backup-s3-access"
      Application = "postgresql"
    }
  )
}

# Attach the policy to the PostgreSQL user
resource "aws_iam_user_policy_attachment" "postgresql_backup_s3_access" {
  user       = aws_iam_user.postgresql_backup.name
  policy_arn = aws_iam_policy.postgresql_backup_s3_access.arn
}

# Alternative: Configure using the s3-iam-access module
# Uncomment this section if you prefer to use an IAM role instead of a user

# module "s3_iam_access" {
#   source = "../../modules/s3-iam-access"
#   
#   bucket_access_configs = {
#     longhorn_backups = {
#       bucket_name = module.s3_buckets.bucket_ids["longhorn_backups_home_ops"]
#       bucket_arn  = module.s3_buckets.bucket_arns["longhorn_backups_home_ops"]
#       
#       role_access = [
#         {
#           role_name   = "longhorn-backup-role"
#           role_arn    = aws_iam_role.longhorn_backup.arn
#           permissions = [
#             "s3:ListBucket",
#             "s3:GetBucketLocation",
#             "s3:GetObject",
#             "s3:PutObject",
#             "s3:DeleteObject",
#             "s3:GetObjectVersion",
#             "s3:DeleteObjectVersion"
#           ]
#         }
#       ]
#       
#       cross_account_access = []
#     }
#   }
#   
#   common_tags = local.common_tags
# }

# Outputs for Longhorn configuration
output "longhorn_backup_access_key_id" {
  description = "Access key ID for Longhorn backup user"
  value       = aws_iam_access_key.longhorn_backup.id
  sensitive   = true
}

output "longhorn_backup_secret_access_key" {
  description = "Secret access key for Longhorn backup user"
  value       = aws_iam_access_key.longhorn_backup.secret
  sensitive   = true
}

output "longhorn_backup_bucket_name" {
  description = "S3 bucket name for Longhorn backups"
  value       = module.s3_buckets.bucket_ids["longhorn_backups_home_ops"]
}

output "longhorn_backup_bucket_region" {
  description = "AWS region for Longhorn backup bucket"
  value       = var.aws_region
}

# Instructions for Longhorn configuration
output "longhorn_configuration_instructions" {
  description = "Instructions for configuring Longhorn with S3 backup"
  value       = <<-EOT
    To configure Longhorn with S3 backup:
    
    1. Get the credentials:
       - Access Key ID: terraform output -raw longhorn_backup_access_key_id
       - Secret Access Key: terraform output -raw longhorn_backup_secret_access_key
    
    2. In Longhorn UI or via kubectl, configure the backup target:
       - Backup Target: s3://${module.s3_buckets.bucket_ids["longhorn_backups_home_ops"]}@${var.aws_region}/
       - Backup Target Credential Secret: Create a Kubernetes secret with the AWS credentials
    
    3. Create the Kubernetes secret:
       kubectl create secret generic longhorn-backup-secret \
         --from-literal=AWS_ACCESS_KEY_ID=$(terraform output -raw longhorn_backup_access_key_id) \
         --from-literal=AWS_SECRET_ACCESS_KEY=$(terraform output -raw longhorn_backup_secret_access_key) \
         -n longhorn-system
    
    4. Configure Longhorn to use the secret for backup credentials.
  EOT
}

# Outputs for PostgreSQL configuration
output "postgresql_backup_access_key_id" {
  description = "Access key ID for PostgreSQL backup user"
  value       = aws_iam_access_key.postgresql_backup.id
  sensitive   = true
}

output "postgresql_backup_secret_access_key" {
  description = "Secret access key for PostgreSQL backup user"
  value       = aws_iam_access_key.postgresql_backup.secret
  sensitive   = true
}

output "postgresql_backup_bucket_name" {
  description = "S3 bucket name for PostgreSQL backups"
  value       = module.s3_buckets.bucket_ids["postgresql_backup_home_ops"]
}

output "postgresql_backup_bucket_region" {
  description = "AWS region for PostgreSQL backup bucket"
  value       = var.aws_region
}

# Instructions for PostgreSQL configuration
output "postgresql_configuration_instructions" {
  description = "Instructions for configuring PostgreSQL with S3 backup"
  value       = <<-EOT
    To configure PostgreSQL with S3 backup:
    
    1. Get the credentials:
       - Access Key ID: terraform output -raw postgresql_backup_access_key_id
       - Secret Access Key: terraform output -raw postgresql_backup_secret_access_key
    
    2. Configure your PostgreSQL backup script or tool with:
       - Bucket: ${module.s3_buckets.bucket_ids["postgresql_backup_home_ops"]}
       - Region: ${var.aws_region}
       - AWS Access Key ID: (from step 1)
       - AWS Secret Access Key: (from step 1)
    
    3. Example environment variables for backup scripts:
       export AWS_ACCESS_KEY_ID=$(terraform output -raw postgresql_backup_access_key_id)
       export AWS_SECRET_ACCESS_KEY=$(terraform output -raw postgresql_backup_secret_access_key)
       export S3_BUCKET=${module.s3_buckets.bucket_ids["postgresql_backup_home_ops"]}
       export AWS_REGION=${var.aws_region}
    
    4. The bucket has lifecycle rules configured:
       - Backups expire after 90 days
       - Non-current versions expire after 30 days
  EOT
}