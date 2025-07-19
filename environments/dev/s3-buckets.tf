# S3 Buckets Configuration
# Auto-configured based on discovered buckets

module "s3_buckets" {
  source = "../../modules/s3-buckets"

  buckets = {
    # Home Assistant backups bucket
    home_assistant_backups_hassio_pi = {
      bucket_name = "home-assistant-backups-hassio-pi"
      acl         = "private"

      server_side_encryption = {
        algorithm          = "AES256"
        bucket_key_enabled = true
      }

      public_access_block = {
        block_public_acls       = true
        block_public_policy     = true
        ignore_public_acls      = true
        restrict_public_buckets = true
      }

      tags = {
        application = "home-assistant"
      }
    }

    # Longhorn backups bucket
    longhorn_backups_home_ops = {
      bucket_name = "longhorn-backups-home-ops"
      acl         = "private"

      server_side_encryption = {
        algorithm          = "AES256"
        bucket_key_enabled = true
      }

      public_access_block = {
        block_public_acls       = true
        block_public_policy     = true
        ignore_public_acls      = true
        restrict_public_buckets = true
      }

      tags = {
        application = "longhorn"
        purpose     = "kubernetes-backups"
      }
    }

    # PostgreSQL backups bucket
    postgresql_backup_home_ops = {
      bucket_name = "postgresql-backup-home-ops"
      acl         = "private"

      server_side_encryption = {
        algorithm          = "AES256"
        bucket_key_enabled = true
      }

      public_access_block = {
        block_public_acls       = true
        block_public_policy     = true
        ignore_public_acls      = true
        restrict_public_buckets = true
      }

      lifecycle_rules = [
        {
          id                         = "postgresql_backup_retention"
          enabled                    = true
          prefix                     = ""
          expiration_days            = 90
          noncurrent_expiration_days = 30
        }
      ]

      tags = {
        application = "postgresql"
        purpose     = "database-backups"
      }
    }
  }

  common_tags = local.common_tags
}

# Outputs to reference bucket information
output "s3_bucket_ids" {
  description = "Map of bucket names to IDs"
  value       = module.s3_buckets.bucket_ids
}

output "s3_bucket_arns" {
  description = "Map of bucket names to ARNs"
  value       = module.s3_buckets.bucket_arns
}