# home-iac

OpenTofu (Terraform) configuration for home lab AWS infrastructure.

## What it manages

- **S3 buckets** for backups (Longhorn, Home Assistant, PostgreSQL)
- **IAM users and policies** for backup service accounts
- **State backend** (S3 bucket + DynamoDB lock table)

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.5.0
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`)
- [Task](https://taskfile.dev/) runner
- AWS credentials stored in 1Password

## Usage

```bash
cp .env.example .env   # edit with your 1Password item references
task init              # initialize OpenTofu
task plan              # preview changes
task apply             # apply changes
```

## Structure

```
environments/
  home/                # home lab environment
    backend.tf         # S3 remote state backend
    main.tf            # AWS provider + common tags
    versions.tf        # provider version constraints
    state-backend.tf   # state bucket + DynamoDB table resources
    s3-buckets.tf      # workload S3 buckets
    s3-iam-access.tf   # IAM users + policies for backup access
    variables.tf       # input variables
modules/
  s3-buckets/          # reusable S3 bucket module
```

## State backend

State is stored in S3 (`opentofu-state-home-iac-<account-id>`) with DynamoDB locking.
If the state bucket is destroyed, bootstrap with local state first:

1. Temporarily switch `backend.tf` to `backend "local" {}`
2. `tofu init -reconfigure && tofu apply -target=aws_s3_bucket.terraform_state -target=aws_dynamodb_table.terraform_locks`
3. Restore the S3 backend config and `tofu init -migrate-state`
