# Documented Tasks

This file contains documented workflows for repetitive tasks that follow similar patterns and require editing the same files.

## Add New S3 Backup Service

**Last performed:** 2025-07-31
**Files to modify:**

- `environments/dev/s3-buckets.tf` - Add S3 bucket configuration
- `environments/dev/s3-iam-access.tf` - Add IAM user, policy, and access key
- `scripts/lib/service_configs.py` - Add service configuration for credential management
- `Taskfile.yml` - Add service-specific credential management tasks

**Steps:**

1. **Add S3 bucket configuration** in `environments/dev/s3-buckets.tf`:
   - Add new bucket entry to the `buckets` map in the `s3_buckets` module
   - Configure encryption (AES256), ACL (private), public access blocking
   - Add lifecycle rules if needed (typically 90-day expiration, 30-day non-current version expiration)
   - Add appropriate tags (application, purpose)

2. **Add IAM resources** in `environments/dev/s3-iam-access.tf`:
   - Create IAM user with `/system/` path and appropriate tags
   - Create IAM access key with time-based rotation trigger
   - Create IAM policy with least-privilege S3 permissions (ListBucket, GetObject, PutObject, DeleteObject)
   - Attach policy to user
   - Add outputs for access key ID, secret access key, bucket name, and region
   - Add configuration instructions output with examples

3. **Add service configuration** in `scripts/lib/service_configs.py`:
   - Add new service entry to `SERVICE_CONFIGS` dictionary
   - Configure service name, terraform output prefix, 1Password item title and vault
   - Set appropriate tags and description
   - Specify S3 bucket name and AWS region

4. **Add Taskfile tasks** in `Taskfile.yml`:
   - Add `creds:service-name` task for credential updates
   - Add `creds:rotate:service-name` task for full credential rotation cycle
   - Follow existing patterns from postgresql and longhorn services

5. **Test the workflow**:
   - Run `task dev:plan` to validate configuration
   - Run `task dev:apply` to provision resources
   - Run `task creds:service-name` to store credentials in 1Password
   - Verify credentials with `task creds:verify SERVICE=service-name`

**Important notes:**

- Follow existing naming conventions: `service-backup-user`, `service-backup-s3-access`, `service-backup-home-ops`
- Use consistent terraform output prefixes that match the service configuration
- Ensure 1Password item titles follow the pattern: "AWS Access Key - service-s3-backup - home-ops"
- Store credentials in the "Automation" vault
- Include comprehensive configuration instructions in the terraform outputs
- Test credential management workflow end-to-end

**Example implementation:**

For a service called "home-assistant-postgres":
- Bucket: `home-assistant-postgres-backup-home-ops`
- IAM User: `home-assistant-postgres-backup-user`
- IAM Policy: `home-assistant-postgres-backup-s3-access`
- Terraform Output Prefix: `home_assistant_postgres_backup`
- 1Password Item: "AWS Access Key - home-assistant-postgres-s3-backup - home-ops"
- Tasks: `creds:home-assistant-postgres`, `creds:rotate:home-assistant-postgres`