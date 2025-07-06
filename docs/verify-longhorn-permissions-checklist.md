# Longhorn S3 Permissions Verification Checklist

This checklist helps verify that the IAM permissions for the Longhorn S3 backup bucket (`longhorn-backups-home-ops`) are correctly configured.

## Prerequisites

1. **1Password Item**: `AWS Access Key - longhorn-s3-backup - home-ops`
   - Should contain AWS Access Key ID and Secret Access Key
   - Should be stored in the `Private` vault

2. **S3 Bucket**: `longhorn-backups-home-ops`
   - Should exist in your AWS account
   - Should have encryption enabled
   - Should have public access blocked

## Manual Verification Steps

### Step 1: Retrieve Credentials from 1Password

```bash
# Set up environment
source .env

# Get the AWS credentials
op item get "AWS Access Key - longhorn-s3-backup - home-ops" --vault Private --account "${OP_ACCOUNT}"
```

### Step 2: Configure AWS CLI with Longhorn Credentials

```bash
# Export the credentials (replace with actual values from 1Password)
export AWS_ACCESS_KEY_ID="<access-key-from-1password>"
export AWS_SECRET_ACCESS_KEY="<secret-key-from-1password>"
export AWS_DEFAULT_REGION="us-west-2"

# Verify identity
aws sts get-caller-identity
```

### Step 3: Test Required Permissions

Run these commands to verify each required permission:

#### 1. s3:ListBucket
```bash
# Should list bucket contents without error
aws s3 ls s3://longhorn-backups-home-ops/
```
✅ Required for: Listing existing backups

#### 2. s3:GetBucketLocation
```bash
# Should return the bucket's region
aws s3api get-bucket-location --bucket longhorn-backups-home-ops
```
✅ Required for: Determining bucket region for API calls

#### 3. s3:GetObject
```bash
# Create a test file first
echo "test" | aws s3 cp - s3://longhorn-backups-home-ops/test-read.txt

# Try to read it
aws s3 cp s3://longhorn-backups-home-ops/test-read.txt -

# Clean up
aws s3 rm s3://longhorn-backups-home-ops/test-read.txt
```
✅ Required for: Restoring from backups

#### 4. s3:PutObject
```bash
# Should successfully upload
echo "test write" | aws s3 cp - s3://longhorn-backups-home-ops/test-write.txt

# Clean up
aws s3 rm s3://longhorn-backups-home-ops/test-write.txt
```
✅ Required for: Creating new backups

#### 5. s3:DeleteObject
```bash
# Create then delete a test file
echo "test delete" | aws s3 cp - s3://longhorn-backups-home-ops/test-delete.txt
aws s3 rm s3://longhorn-backups-home-ops/test-delete.txt
```
✅ Required for: Cleaning up old backups

### Step 4: Check Optional Permissions (if versioning is enabled)

```bash
# Check if versioning is enabled
aws s3api get-bucket-versioning --bucket longhorn-backups-home-ops

# If versioning is enabled, also test:
# - s3:GetObjectVersion
# - s3:DeleteObjectVersion
```

## Expected IAM Policy

The IAM user should have a policy similar to:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::longhorn-backups-home-ops"
    },
    {
      "Sid": "ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "arn:aws:s3:::longhorn-backups-home-ops/*"
    }
  ]
}
```

## Configuring Longhorn

Once permissions are verified:

1. **Create Kubernetes Secret**:
   ```bash
   kubectl create secret generic longhorn-backup-secret \
     --from-literal=AWS_ACCESS_KEY_ID='<access-key-id>' \
     --from-literal=AWS_SECRET_ACCESS_KEY='<secret-access-key>' \
     -n longhorn-system
   ```

2. **Configure Backup Target in Longhorn UI**:
   - Backup Target: `s3://longhorn-backups-home-ops@us-west-2/`
   - Backup Target Credential Secret: `longhorn-backup-secret`

## Troubleshooting

### Common Issues

1. **"Access Denied" errors**
   - Verify the IAM policy is attached to the user
   - Check the bucket name is correct
   - Ensure the resource ARNs in the policy match the bucket

2. **"NoSuchBucket" errors**
   - Verify the bucket exists
   - Check the region is correct

3. **Cannot create/restore backups**
   - Verify all required permissions are granted
   - Check Kubernetes secret is created correctly
   - Ensure Longhorn can access the secret

### Debug Commands

```bash
# Check current user/role
aws sts get-caller-identity

# List all policies attached to a user
aws iam list-attached-user-policies --user-name <username>

# Get policy details
aws iam get-policy --policy-arn <policy-arn>
aws iam get-policy-version --policy-arn <policy-arn> --version-id <version>

# Check bucket policy (if any)
aws s3api get-bucket-policy --bucket longhorn-backups-home-ops

# Check bucket encryption
aws s3api get-bucket-encryption --bucket longhorn-backups-home-ops

# Check public access block
aws s3api get-public-access-block --bucket longhorn-backups-home-ops
```

## Summary

For Longhorn to successfully use S3 as a backup target, ensure:

- [ ] IAM user exists with access keys
- [ ] All 5 required permissions are granted
- [ ] Credentials are stored in 1Password
- [ ] Kubernetes secret is created with credentials
- [ ] Longhorn is configured with correct backup target URL
- [ ] Backup target credential secret is set in Longhorn

If any permission test fails, update the IAM policy to include the missing permissions.