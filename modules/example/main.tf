# Example reusable module for AWS resources
resource "aws_s3_bucket" "example" {
  bucket = var.bucket_name
}

variable "bucket_name" {
  description = "The name of the S3 bucket."
  type        = string
}
