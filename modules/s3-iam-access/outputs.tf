# Outputs for S3 IAM Access Module

output "bucket_policies" {
  description = "Map of bucket names to their policy documents"
  value       = { for k, v in aws_s3_bucket_policy.role_access : k => v.policy }
}

output "iam_policies" {
  description = "Map of created IAM policies"
  value = {
    for k, v in aws_iam_policy.bucket_access : k => {
      arn  = v.arn
      name = v.name
    }
  }
}

output "role_attachments" {
  description = "Map of role policy attachments"
  value = {
    for k, v in aws_iam_role_policy_attachment.bucket_access : k => {
      role       = v.role
      policy_arn = v.policy_arn
    }
  }
}