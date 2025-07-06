# OpenTofu Infrastructure as Code for AWS S3 Management

This repository manages AWS S3 infrastructure using OpenTofu (Terraform-compatible) with 1Password integration for secure credential management.

## 🚀 Quick Start

```bash
# 1. Set up environment
cp .env.example .env
# Edit .env with your 1Password account

# 2. Source environment and run setup
source .env
./scripts/init-setup.sh

# 3. Set AWS credentials from 1Password
source scripts/set-aws-credentials.sh

# 4. Run OpenTofu
cd environments/dev
tofu plan
tofu apply
```

## 📋 Prerequisites

- **mise** (recommended) or manually installed tools:
  - **OpenTofu** (v1.5.0+)
  - **AWS CLI** configured
  - **1Password CLI** installed and configured
  - **jq** for JSON processing
- AWS credentials stored in 1Password (configure location in .env)

### Automated Tool Installation

This project uses [mise](https://mise.jdx.dev) for managing tool versions:

```bash
# Install mise and all required tools
./scripts/setup-mise.sh
```

See [docs/dependency-management.md](docs/dependency-management.md) for details.

## 🏗️ Architecture

### Repository Structure

```
.
├── environments/          # Environment-specific configurations
│   └── dev/              # Development environment
│       ├── main.tf       # Provider configuration
│       ├── backend.tf    # S3 + DynamoDB state backend
│       ├── s3-buckets.tf # S3 bucket configurations
│       └── state-backend.tf # State storage infrastructure
├── modules/              # Reusable OpenTofu modules
│   ├── s3-buckets/      # S3 bucket management
│   └── s3-iam-access/   # IAM access policies
├── scripts/             # Automation scripts
│   ├── init-setup.sh    # Initial setup script
│   ├── discover-s3-buckets.sh # S3 discovery
│   └── import-with-credentials.sh # Import helper
└── docs/                # Additional documentation
```

### State Management

- **State Storage**: S3 bucket `opentofu-state-home-iac-078129923125`
- **State Locking**: DynamoDB table `opentofu-state-locks-home-iac`
- **Encryption**: AES256 at rest
- **Versioning**: Enabled for state history

## 🔧 Configuration

### 1Password Setup

Your AWS credentials must be stored in 1Password. Configure the location in `.env`:
```bash
OP_AWS_VAULT=Private
OP_AWS_ITEM="AWS Access Key - S3 - Personal"
OP_AWS_ACCESS_KEY_FIELD="access key id"
OP_AWS_SECRET_KEY_FIELD="secret access key"
OP_AWS_SECTION="Section_name"  # If using sections
```

### Environment Variables

Copy and update `.env` file:
```bash
cp .env.example .env
# Edit .env with your 1Password configuration
```

### AWS IAM Requirements

Your IAM user needs:
- **S3 Permissions**: Full access to S3 buckets
- **DynamoDB Permissions**: For state locking (see `docs/complete-dynamodb-permissions.json`)

## 📚 Module Documentation

### S3 Buckets Module

Manages S3 buckets with support for:
- Versioning and encryption
- Lifecycle rules
- Public access blocks
- Bucket policies
- Tags

Example usage:
```hcl
module "s3_buckets" {
  source = "../../modules/s3-buckets"
  
  buckets = {
    my_bucket = {
      bucket_name = "my-unique-bucket-name"
      versioning  = true
      
      server_side_encryption = {
        algorithm          = "AES256"
        bucket_key_enabled = true
      }
      
      tags = {
        Purpose = "Data Storage"
      }
    }
  }
}
```

### S3 IAM Access Module

Manages IAM access to S3 buckets:
```hcl
module "s3_iam_access" {
  source = "../../modules/s3-iam-access"
  
  bucket_access_configs = {
    my_bucket = {
      bucket_name = "my-unique-bucket-name"
      bucket_arn  = module.s3_buckets.bucket_arns["my_bucket"]
      
      role_access = [{
        role_name   = "MyApplicationRole"
        role_arn    = "arn:aws:iam::123456789012:role/MyApplicationRole"
        permissions = ["s3:GetObject", "s3:PutObject"]
      }]
    }
  }
}
```

## 🔄 Common Operations

### Import Existing S3 Buckets

```bash
# Discover existing buckets
./scripts/discover-s3-buckets.sh

# Review discovered configuration
cat discovered-buckets.json

# Import buckets
cd environments/dev
../../scripts/import-with-credentials.sh
```

### Set AWS Credentials

```bash
# Option 1: Use the convenience script (recommended)
source scripts/set-aws-credentials.sh

# Option 2: Set manually
source .env
export AWS_ACCESS_KEY_ID=$(op read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_ACCESS_KEY_FIELD}")
export AWS_SECRET_ACCESS_KEY=$(op read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_SECRET_KEY_FIELD}")
```

### Add New S3 Bucket

1. Add configuration to `environments/dev/s3-buckets.tf`
2. Run `tofu plan` to preview
3. Run `tofu apply` to create

### Enable State Locking

If you have DynamoDB permissions:
```bash
./scripts/setup-dynamodb-locking.sh
```

## 🛠️ Troubleshooting

### 1Password Authentication Issues

```bash
# Ensure you're signed in
op signin

# Test credential access (using vars from .env)
source .env
op item get "${OP_AWS_ITEM}" --vault "${OP_AWS_VAULT}"
```

### AWS Credentials Not Working

Check the 1Password item structure matches your .env configuration:
- Verify vault name, item name, and field names in .env
- Update OP_AWS_SECTION if your item uses sections

### State Lock Errors

If DynamoDB locking fails:
1. Check IAM permissions (see `docs/complete-dynamodb-permissions.json`)
2. Verify table exists: `aws dynamodb list-tables --region us-west-2`
3. Force unlock if needed: `tofu force-unlock <LOCK_ID>`

## 🔐 Security Best Practices

1. **Never commit credentials** - Use 1Password integration
2. **Use least-privilege IAM policies**
3. **Enable bucket encryption** for all S3 buckets
4. **Enable versioning** for critical buckets
5. **Regular credential rotation**
6. **Use separate AWS accounts** for different environments

## 🚢 CI/CD Integration

For GitOps workflows:

1. Store AWS credentials in CI/CD secrets
2. Use PR checks to run `tofu plan`
3. Apply changes on merge to main
4. Use workspaces for multiple environments

Example GitHub Actions workflow:
```yaml
name: Terraform Plan
on: [pull_request]

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      
      - name: Terraform Plan
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          cd environments/dev
          terraform init
          terraform plan
```

## 🔄 Dependency Management

This project uses:
- **mise**: Runtime version management for consistent tool versions
- **Renovate**: Automated dependency updates via pull requests

Dependencies are automatically updated weekly. See [docs/dependency-management.md](docs/dependency-management.md) for details.

## 📖 Additional Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [mise Documentation](https://mise.jdx.dev)
- [Renovate Documentation](https://docs.renovatebot.com/)

## 🤝 Contributing

1. Create feature branch
2. Make changes
3. Run `tofu fmt` and `tofu validate`
4. Submit PR with plan output

---

For detailed setup instructions, see [docs/setup-guide.md](docs/setup-guide.md)
