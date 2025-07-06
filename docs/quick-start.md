# Quick Start Guide

This guide will get you up and running with OpenTofu S3 management in minutes.

## Prerequisites

- OpenTofu or Terraform installed
- AWS CLI installed
- 1Password CLI installed
- jq installed (for JSON processing)
- AWS credentials stored in 1Password as "AWS Access Key - S3 - Personal" in the "Private" vault

## Step 1: Run Initial Setup

From the repository root directory:

```bash
# Make sure you're in the project root
cd /Users/gadavis/src/personal/home-iac

# Run the initialization script
./scripts/init-setup.sh
```

This script will:
1. Check all prerequisites
2. Set up your environment
3. Test 1Password authentication
4. Verify AWS access
5. Initialize OpenTofu with local state
6. Discover your existing S3 buckets

## Step 2: Review Discovered Buckets

After the script completes, review your discovered buckets:

```bash
# View the discovered configuration
cat discovered-buckets.json | jq .
```

## Step 3: Create Bucket Configuration

Copy the example configuration and customize it based on your discovered buckets:

```bash
cp environments/dev/s3-buckets.tf.example environments/dev/s3-buckets.tf
```

Edit `environments/dev/s3-buckets.tf` to match your actual buckets. Use the discovered configuration as a reference.

## Step 4: Import Existing Buckets

The discovery script created an import script. Run it to import your buckets:

```bash
cd environments/dev
../../scripts/import-s3-buckets.sh
```

## Step 5: Verify Configuration

Check that everything is correctly imported:

```bash
tofu plan
```

The plan should show no changes if your configuration matches the existing buckets.

## Troubleshooting

### 1Password Authentication Issues

If you get authentication errors:
```bash
# Sign in to 1Password CLI
op signin

# Verify you can access the item
op item get "AWS Access Key - S3 - Personal" --vault Private
```

### AWS Credentials Structure

The configuration expects your 1Password item to have AWS credentials as:
- Username field: AWS Access Key ID
- Password field: AWS Secret Access Key

If your item has a different structure, update `environments/dev/main.tf` accordingly.

### OpenTofu Init Errors

If initialization fails:
1. Ensure the backend configuration in `environments/dev/backend.tf` is commented out
2. Check that all provider versions are compatible
3. Try removing `.terraform` directory and reinitializing

## Next Steps

1. **Enable Remote State** (optional but recommended):
   - Create an S3 bucket for state storage
   - Uncomment the backend configuration in `environments/dev/backend.tf`
   - Run `tofu init -migrate-state`

2. **Set Up IAM Access**:
   - Configure role-based access using the `s3-iam-access` module
   - See examples in the setup guide

3. **Implement GitOps**:
   - Create feature branches for changes
   - Use pull requests with plan reviews
   - Set up CI/CD for automated applies

For more detailed information, see the [Complete Setup Guide](./setup-guide.md).