# Credential Management Framework

A modular Python framework for managing AWS IAM credentials with automatic rotation and 1Password integration.

## Overview

This framework provides a reusable system for:
- Creating AWS IAM users and access keys via Terraform
- Implementing credential rotation using time-based triggers
- Securely storing credentials in 1Password
- Managing multiple services with consistent patterns

## Quick Start

### Update Existing Service Credentials

**Using Taskfile (Recommended):**
```bash
# List available services
task creds:list

# Update PostgreSQL backup credentials
task creds:postgresql

# Update Longhorn backup credentials
task creds:longhorn

# Update any service by name
task creds:update SERVICE=<service-name>
```

**Direct Python commands:**
```bash
# List available services
python3 scripts/update-credentials.py --list

# Update PostgreSQL backup credentials
python3 scripts/update-credentials.py postgresql

# Update Longhorn backup credentials
python3 scripts/update-credentials.py longhorn
```

### Add a New Service

1. **Generate configuration template:**
   ```bash
   python3 scripts/generate-service-config.py --interactive
   ```

2. **Add Terraform configuration** to `environments/dev/s3-iam-access.tf`

3. **Add S3 bucket configuration** to `environments/dev/s3-buckets.tf`

4. **Add service config** to `scripts/lib/service_configs.py`

5. **Deploy and update credentials:**
   ```bash
   cd environments/dev
   tofu plan
   tofu apply
   cd ../..
   python3 scripts/update-credentials.py <service-name>
   ```

## Architecture

### Core Components

- **`credential_manager.py`**: Core framework classes
  - `CredentialManager`: Main orchestrator
  - `TerraformCredentialProvider`: Retrieves credentials from Terraform
  - `OnePasswordStorage`: Handles 1Password operations
  - `CredentialConfig`: Configuration data structure

- **`service_configs.py`**: Service-specific configurations
- **`update-credentials.py`**: Main CLI interface
- **`generate-service-config.py`**: Configuration generator

### Data Flow

```
Terraform Outputs → CredentialProvider → CredentialManager → 1Password Storage
                                      ↑
                              Service Configuration
```

## Configuration Structure

Each service is defined with a `CredentialConfig`:

```python
CredentialConfig(
    service_name="PostgreSQL S3 Backup",
    terraform_output_prefix="postgresql_backup",
    onepassword_item_title="AWS Access Key - postgresql-s3-backup - home-ops",
    onepassword_vault="Automation",
    tags=["aws", "postgresql", "s3", "backup", "database"],
    description="AWS IAM credentials for PostgreSQL S3 backup access.",
    s3_bucket_name="postgresql-backup-home-ops",
    aws_region="us-west-2"
)
```

## Terraform Integration

### Required Terraform Resources

For each service, the following resources are created:

1. **IAM User**: `aws_iam_user.<service>_backup`
2. **Access Key**: `aws_iam_access_key.<service>_backup`
3. **Rotation Trigger**: `time_rotating.<service>_backup_rotation`
4. **IAM Policy**: `aws_iam_policy.<service>_backup_s3_access`
5. **Policy Attachment**: `aws_iam_user_policy_attachment.<service>_backup_s3_access`

### Required Terraform Outputs

```hcl
output "<service>_backup_access_key_id" {
  description = "Access key ID for <service> backup user"
  value       = aws_iam_access_key.<service>_backup.id
  sensitive   = true
}

output "<service>_backup_secret_access_key" {
  description = "Secret access key for <service> backup user"
  value       = aws_iam_access_key.<service>_backup.secret
  sensitive   = true
}
```

## 1Password Integration

### Item Structure

Credentials are stored as "API Credential" items with:
- **Title**: `AWS Access Key - <service>-s3-backup - home-ops`
- **Username**: AWS Access Key ID
- **Password**: AWS Secret Access Key
- **Tags**: Service-specific tags for organization
- **Notes**: Description and management information

### Vault Organization

- **Default Vault**: `Automation`
- **Configurable**: Can be overridden per service

## Security Features

- **No credential exposure**: Secret keys never appear in terminal output
- **Secure retrieval**: Uses Terraform's sensitive outputs
- **Automatic rotation**: Time-based triggers force credential regeneration
- **Least privilege**: IAM policies follow principle of least privilege
- **Audit trail**: All operations logged with colored output

## Examples

### Adding a Redis Service

1. **Interactive generation:**
   ```bash
   python3 scripts/generate-service-config.py --interactive
   # Follow prompts for Redis configuration
   ```

2. **Add generated Terraform to `s3-iam-access.tf`**

3. **Add S3 bucket to `s3-buckets.tf`:**
   ```hcl
   redis_backup_home_ops = {
     application = "redis"
     purpose     = "database-backups"
     lifecycle_rules = [
       {
         id     = "redis_backup_retention"
         status = "Enabled"
         expiration = {
           days = 90
         }
         noncurrent_version_expiration = {
           noncurrent_days = 30
         }
       }
     ]
   }
   ```

4. **Add to `service_configs.py`:**
   ```python
   "redis": CredentialConfig(
       service_name="Redis S3 Backup",
       terraform_output_prefix="redis_backup",
       onepassword_item_title="AWS Access Key - redis-s3-backup - home-ops",
       onepassword_vault="Automation",
       tags=["aws", "redis", "s3", "backup", "database"],
       description="AWS IAM credentials for Redis S3 backup access.",
       s3_bucket_name="redis-backup-home-ops",
       aws_region="us-west-2"
   )
   ```

5. **Deploy and update:**
   ```bash
   cd environments/dev && tofu apply && cd ../..
   python3 scripts/update-credentials.py redis
   ```

## Migration from Legacy Scripts

The framework replaces individual service scripts like:
- `update-longhorn-1password-credentials.sh`
- `update-postgresql-1password-credentials.py`

Legacy scripts can be removed after verifying the modular system works correctly.

## Taskfile Integration

The credential management framework is fully integrated with the project's Taskfile for streamlined operations:

### Available Tasks

```bash
# Credential Management
task creds:list                    # List all available services
task creds:postgresql              # Update PostgreSQL credentials
task creds:longhorn                # Update Longhorn credentials
task creds:update SERVICE=<name>   # Update any service credentials
task creds:generate                # Generate new service configuration
task creds:show SERVICE=<name>     # Show service configuration
task creds:rotate SERVICE=<name>   # Full rotation (Terraform + 1Password)

# Full Rotation Examples
task creds:rotate:postgresql       # Complete PostgreSQL credential rotation
task creds:rotate:longhorn         # Complete Longhorn credential rotation
```

### Workflow Integration

The Taskfile tasks integrate with existing workflows:

1. **`creds:rotate`** - Combines Terraform apply with credential updates
2. **AWS authentication** - Uses existing `aws:auth` dependency
3. **Environment management** - Respects `ENVIRONMENT` variable
4. **Error handling** - Includes precondition checks

### Example Workflows

**Complete credential rotation:**
```bash
# Plan, apply, and update credentials in one command
task creds:rotate SERVICE=postgresql
```

**Development workflow:**
```bash
# List services and update specific one
task creds:list
task creds:postgresql
```

**Adding new service:**
```bash
# Generate configuration interactively
task creds:generate
# Follow prompts, then apply Terraform changes
task plan && task apply
# Update credentials
task creds:update SERVICE=<new-service>
```

## Troubleshooting

### Common Issues

1. **Import errors**: Ensure you're running from the repository root
2. **Terraform errors**: Verify AWS credentials are set via `scripts/set-aws-credentials.sh`
3. **1Password errors**: Check `OP_ACCOUNT` in `.env` file
4. **Missing outputs**: Ensure Terraform outputs match the expected naming pattern
5. **Task errors**: Run `task --list` to see all available tasks

### Debug Mode

Add debug output by modifying the `Colors` class or adding verbose logging to the credential manager.

## Future Enhancements

- **Automatic rotation scheduling**: Integrate with cron or systemd timers
- **Multi-environment support**: Extend to staging/production environments
- **Backup verification**: Test credentials after rotation
- **Notification system**: Alert on rotation success/failure
- **Web interface**: GUI for credential management