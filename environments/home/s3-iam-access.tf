# IAM users and policies for S3 backup access.
# Access keys are managed in 1Password, not here.

# --- Home Assistant backup user ---

resource "aws_iam_user" "home_assistant_backup" {
  name = "home-assistant-backup"
  tags = merge(local.common_tags, { Application = "home-assistant" })
}

resource "aws_iam_policy" "home_assistant_backup_s3_access" {
  name        = "HomeAssistantS3Policy"
  description = "Home Assistant S3 backup bucket access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BackupOperations"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          module.s3_buckets.bucket_arns["home_assistant_backups_hassio_pi"],
          "${module.s3_buckets.bucket_arns["home_assistant_backups_hassio_pi"]}/*"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, { Application = "home-assistant" })
}

resource "aws_iam_user_policy_attachment" "home_assistant_backup_s3_access" {
  user       = aws_iam_user.home_assistant_backup.name
  policy_arn = aws_iam_policy.home_assistant_backup_s3_access.arn
}
