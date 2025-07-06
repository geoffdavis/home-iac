# OpenTofu GitOps Repository for AWS S3 Management

This repository manages AWS S3 infrastructure using OpenTofu (Terraform-compatible) with 1Password integration for secure credential management.

## Features

- 🔐 **Secure credential management** with 1Password CLI integration
- 🪣 **S3 bucket management** with comprehensive configuration options
- 👥 **IAM access management** for role-based bucket access
- 🔍 **Discovery tooling** to import existing S3 buckets
- 📊 **State management** with S3 backend and DynamoDB locking
- 📚 **Comprehensive documentation** for setup and usage

## Repository Structure

```
.
├── environments/          # Per-environment configurations
│   └── dev/              # Development environment
│       ├── main.tf       # Main configuration with providers
│       ├── backend.tf    # State backend configuration
│       └── versions.tf   # Provider version constraints
├── modules/              # Reusable OpenTofu modules
│   ├── s3-buckets/      # S3 bucket management module
│   └── s3-iam-access/   # IAM access policies module
├── scripts/             # Utility scripts
│   └── discover-s3-buckets.sh  # Discover existing S3 buckets
└── docs/                # Documentation
    ├── setup-guide.md   # Complete setup instructions
    └── 1password-setup.md  # 1Password configuration guide
```

## Quick Start

1. **Prerequisites**
   - Install [OpenTofu](https://opentofu.org/)
   - Install [1Password CLI](https://developer.1password.com/docs/cli/)
   - Configure AWS CLI with appropriate permissions
   - Install `jq` for JSON processing

2. **Initial Setup**
   ```bash
   # Clone the repository
   git clone <repository-url>
   cd home-iac

   # Set up environment
   cp .env.example .env
   # Edit .env with your 1Password account name

   # Follow the setup guide
   open docs/setup-guide.md
   ```

3. **Discover Existing Buckets**
   ```bash
   ./scripts/discover-s3-buckets.sh
   ```

4. **Initialize and Import**
   ```bash
   cd environments/dev
   tofu init
   # Run the generated import script
   ../../scripts/import-s3-buckets.sh
   ```

## Key Components

### S3 Buckets Module

Manages S3 buckets with support for:
- Versioning
- Server-side encryption (SSE-S3, SSE-KMS)
- Lifecycle rules
- Public access blocks
- Bucket policies
- Tags

### S3 IAM Access Module

Manages IAM access to S3 buckets:
- Role-based access policies
- Cross-account access
- Granular permissions
- Path-based restrictions

### 1Password Integration

Securely manages AWS credentials:
- No hardcoded credentials in code
- Credentials stored in 1Password vault
- Retrieved at runtime via 1Password CLI

## Usage Examples

### Managing S3 Buckets

```hcl
module "s3_buckets" {
  source = "../../modules/s3-buckets"
  
  buckets = {
    my_app_data = {
      bucket_name = "my-unique-app-data-bucket"
      versioning  = true
      
      server_side_encryption = {
        algorithm = "AES256"
      }
      
      lifecycle_rules = [{
        id              = "expire-old-versions"
        enabled         = true
        noncurrent_expiration_days = 90
      }]
    }
  }
}
```

### Configuring IAM Access

```hcl
module "s3_iam_access" {
  source = "../../modules/s3-iam-access"
  
  bucket_access_configs = {
    my_app_data = {
      bucket_name = "my-unique-app-data-bucket"
      bucket_arn  = module.s3_buckets.bucket_arns["my_app_data"]
      
      role_access = [{
        role_name   = "MyApplicationRole"
        role_arn    = "arn:aws:iam::123456789012:role/MyApplicationRole"
        permissions = ["s3:GetObject", "s3:PutObject"]
        prefix      = "app-data/"
      }]
    }
  }
}
```

## Best Practices

1. **Version Control**
   - Use branches and PRs for all changes
   - Review plans before applying
   - Tag releases for production deployments

2. **Security**
   - Never commit credentials to Git
   - Use least-privilege IAM policies
   - Enable bucket encryption
   - Regular security audits

3. **State Management**
   - Use remote state with locking
   - Regular state backups
   - Avoid manual state modifications

4. **Resource Organization**
   - Use consistent naming conventions
   - Tag all resources appropriately
   - Separate environments (dev, staging, prod)

## CI/CD Integration

This repository is designed for GitOps workflows:

1. Developer creates branch with changes
2. CI runs `tofu plan` and posts results to PR
3. After review and approval, merge to main
4. CD runs `tofu apply` automatically

## Troubleshooting

See the [Setup Guide](docs/setup-guide.md#troubleshooting) for common issues and solutions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `tofu fmt` and `tofu validate`
5. Create a pull request

## License

[Your license here]
