# Longhorn S3 Backup Permissions

This document explains the IAM permissions required for Longhorn to use an S3 bucket as a backup target.

## Overview

Longhorn is a distributed block storage system for Kubernetes that supports backing up volumes to S3-compatible object storage. To function properly, Longhorn requires specific IAM permissions on the S3 bucket.

## Required Permissions

### Bucket-Level Permissions

These permissions apply to the bucket itself:

- **`s3:ListBucket`**: Required to list objects in the bucket and check if backups exist
- **`s3:GetBucketLocation`**: Required to determine the bucket's region for proper API calls

### Object-Level Permissions

These permissions apply to objects within the bucket:

- **`s3:GetObject`**: Required to read backup data when restoring volumes
- **`s3:PutObject`**: Required to write backup data when creating backups
- **`s3:DeleteObject`**: Required to delete old backups during cleanup operations
- **`s3:GetObjectVersion`**: Required if bucket versioning is enabled (for reading versioned backups)
- **`s3:DeleteObjectVersion`**: Required if bucket versioning is enabled (for deleting old backup versions)

## IAM Policy Example

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

## Security Best Practices

1. **Use a Dedicated IAM User**: Create a specific IAM user for Longhorn rather than using your AWS root account or personal IAM user.

2. **Principle of Least Privilege**: Only grant the minimum permissions required for Longhorn to function.

3. **Bucket Isolation**: Use a dedicated S3 bucket for Longhorn backups, separate from other data.

4. **Enable Encryption**: The bucket is configured with AES256 server-side encryption for data at rest.

5. **Block Public Access**: The bucket has all public access blocked to prevent accidental exposure.

6. **Secure Credential Storage**: Store AWS credentials in Kubernetes secrets and limit access to the namespace where Longhorn is installed.

## Configuration in Terraform

The Terraform configuration in `environments/dev/s3-iam-access.tf` creates:

1. An IAM user: `longhorn-backup-user`
2. Access keys for the user
3. An IAM policy with the required permissions
4. Policy attachment to the user

## Longhorn Configuration

After applying the Terraform configuration:

1. Retrieve the access credentials:
   ```bash
   terraform output -raw longhorn_backup_access_key_id
   terraform output -raw longhorn_backup_secret_access_key
   ```

2. Create a Kubernetes secret:
   ```bash
   kubectl create secret generic longhorn-backup-secret \
     --from-literal=AWS_ACCESS_KEY_ID=<access-key-id> \
     --from-literal=AWS_SECRET_ACCESS_KEY=<secret-access-key> \
     -n longhorn-system
   ```

3. Configure the backup target in Longhorn:
   - Format: `s3://<bucket-name>@<region>/`
   - Example: `s3://longhorn-backups-home-ops@us-west-2/`

## Verification

To verify the permissions are correct:

1. Check if the IAM user can list the bucket:
   ```bash
   aws s3 ls s3://longhorn-backups-home-ops/ --profile longhorn
   ```

2. Test write access:
   ```bash
   echo "test" | aws s3 cp - s3://longhorn-backups-home-ops/test.txt --profile longhorn
   ```

3. Test read access:
   ```bash
   aws s3 cp s3://longhorn-backups-home-ops/test.txt - --profile longhorn
   ```

4. Test delete access:
   ```bash
   aws s3 rm s3://longhorn-backups-home-ops/test.txt --profile longhorn
   ```

## Troubleshooting

Common issues and solutions:

1. **Access Denied errors**: Verify the IAM policy is attached to the user and the bucket name is correct.

2. **Region errors**: Ensure the bucket region matches what's configured in Longhorn.

3. **Credential errors**: Verify the Kubernetes secret contains the correct access keys.

4. **Bucket not found**: Confirm the bucket exists and the name is spelled correctly.

## References

- [Longhorn Documentation - Backup to S3](https://longhorn.io/docs/latest/snapshots-and-backups/backup-and-restore/set-backup-target/#set-up-aws-s3-backupstore)
- [AWS S3 IAM Actions](https://docs.aws.amazon.com/AmazonS3/latest/API/API_Operations.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)