# Outputs for S3 Buckets Module

output "bucket_ids" {
  description = "Map of bucket names to bucket IDs"
  value       = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "bucket_arns" {
  description = "Map of bucket names to bucket ARNs"
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "bucket_domain_names" {
  description = "Map of bucket names to bucket domain names"
  value       = { for k, v in aws_s3_bucket.this : k => v.bucket_domain_name }
}

output "bucket_regional_domain_names" {
  description = "Map of bucket names to bucket regional domain names"
  value       = { for k, v in aws_s3_bucket.this : k => v.bucket_regional_domain_name }
}