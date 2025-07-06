# OpenTofu S3 Management Setup Guide

This guide walks you through setting up OpenTofu to manage your existing AWS S3 buckets with 1Password integration.

## Prerequisites

- OpenTofu installed (v1.5.0 or later)
- AWS CLI configured with access to your account
- 1Password CLI installed and configured
- jq installed (for JSON processing in discovery script)

## Step 1: Configure 1Password

1. Follow the [1Password Setup Guide](./1password-setup.md) to configure 1Password CLI
2. Ensure your AWS credentials are stored in 1Password as described

## Step 2: Set Up Environment

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and set your 1Password account name:
   ```bash
   OP_ACCOUNT=your-account-name
   ```

3. Source the environment file:
   ```bash
   source .env
   ```

## Step 3: Configure State Backend

1. Create an S3 bucket for Terraform state (if you don't have one):
   ```bash
   aws s3 mb s3://your-terraform-state-bucket --region us-east-1
   ```

2. Create a DynamoDB table for state locking (optional but recommended):
   ```bash
   aws dynamodb create-table \
     --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
     --region us-east-1
   ```

3. Update `environments/dev/backend.tf` with your state bucket name:
   ```hcl
   terraform {
     backend "s3" {
       bucket         = "your-terraform-state-bucket"  # Update this
       key            = "home-iac/dev/terraform.tfstate"
       region         = "us-east-1"
       encrypt        = true
       dynamodb_table = "terraform-state-lock"
     }
   }
   ```

## Step 4: Discover Existing S3 Buckets

1. Run the discovery script to find all your S3 buckets:
   ```bash
   ./scripts/discover-s3-buckets.sh
   ```

   This will create:
   - `discovered-buckets.json` - JSON file with all bucket configurations
   - `scripts/import-s3-buckets.sh` - Script to import buckets into state

2. Review the discovered configuration:
   ```bash
   cat discovered-buckets.json | jq .
   ```

## Step 5: Create Bucket Configuration

1. Copy the example configuration:
   ```bash
   cp environments/dev/s3-buckets.tf.example environments/dev/s3-buckets.tf
   ```

2. Edit `environments/dev/s3-buckets.tf` based on your discovered buckets.
   
   Example format:
   ```hcl
   module "s3_buckets" {
     source = "../../modules/s3-buckets"
     
     buckets = {
       my_bucket_key = {
         bucket_name = "actual-bucket-name"
         versioning  = true
         # Add other configurations from discovered-buckets.json
       }
     }
     
     common_tags = local.common_tags
   }
   ```

## Step 6: Configure IAM Access (Optional)

If you have IAM roles that need access to your buckets:

1. Create `environments/dev/s3-iam-access.tf`:
   ```hcl
   module "s3_iam_access" {
     source = "../../modules/s3-iam-access"
     
     bucket_access_configs = {
       my_bucket = {
         bucket_name = module.s3_buckets.bucket_ids["my_bucket_key"]
         bucket_arn  = module.s3_buckets.bucket_arns["my_bucket_key"]
         
         role_access = [
           {
             role_name   = "MyApplicationRole"
             role_arn    = "arn:aws:iam::123456789012:role/MyApplicationRole"
             permissions = ["s3:GetObject", "s3:PutObject"]
           }
         ]
       }
     }
     
     common_tags = local.common_tags
   }
   ```

## Step 7: Initialize and Import

1. Initialize OpenTofu:
   ```bash
   cd environments/dev
   tofu init
   ```

2. If initialization succeeds, run the import script:
   ```bash
   ../../scripts/import-s3-buckets.sh
   ```

   This will import each bucket into your OpenTofu state.

## Step 8: Verify Configuration

1. Run a plan to see if any changes are needed:
   ```bash
   tofu plan
   ```

2. Review the plan output. Ideally, it should show "No changes" if your configuration matches the existing buckets exactly.

3. If there are differences, update your configuration to match the existing state or accept the changes if they're intentional.

## Step 9: Enable Main Configuration

Once everything is imported correctly, uncomment the S3 module in `environments/dev/main.tf`:

```hcl
# Remove the comments from these lines
module "s3_buckets" {
  source = "../../modules/s3-buckets"
  # ... rest of configuration
}
```

## Ongoing Management

### Making Changes

1. Always use branches for changes:
   ```bash
   git checkout -b feature/update-bucket-config
   ```

2. Make your changes to the configuration files

3. Run plan to preview changes:
   ```bash
   tofu plan
   ```

4. Create a pull request for review

5. After approval, apply changes:
   ```bash
   tofu apply
   ```

### Adding New Buckets

1. Add the bucket configuration to `environments/dev/s3-buckets.tf`
2. Run `tofu plan` and `tofu apply`

### Removing Buckets

1. Remove the bucket from configuration
2. Run `tofu plan` to see the deletion
3. If you want to keep the bucket but stop managing it:
   ```bash
   tofu state rm 'module.s3_buckets.aws_s3_bucket.this["bucket_key"]'
   ```

## Troubleshooting

### Import Errors

If import fails for a bucket:
- Check if the bucket name is correct
- Verify you have permissions to access the bucket
- Ensure the bucket key in your configuration matches the import command

### State Lock Errors

If you get state lock errors:
1. Check if another process is running
2. If needed, manually unlock:
   ```bash
   tofu force-unlock <LOCK_ID>
   ```

### 1Password Authentication Issues

See the [1Password Setup Guide](./1password-setup.md) troubleshooting section.

## Best Practices

1. **Always review plans before applying**
2. **Use consistent naming conventions** for bucket keys
3. **Tag all resources** for cost tracking and organization
4. **Enable versioning** on critical buckets
5. **Set up lifecycle rules** to manage storage costs
6. **Use separate environments** (dev, staging, prod) with different state files
7. **Regular backups** of your state file
8. **Audit bucket policies** regularly for security