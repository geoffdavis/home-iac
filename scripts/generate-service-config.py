#!/usr/bin/env python3
"""
Service Configuration Generator
Helps create new service configurations for credential management
"""

import sys
import argparse
from pathlib import Path

# Add the lib directory to the Python path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from credential_manager import CredentialConfig, Colors
from service_configs import add_service_config, SERVICE_CONFIGS


def print_colored(message: str, color: str = Colors.NC) -> None:
    """Print a colored message to stdout"""
    print(f"{color}{message}{Colors.NC}")


def generate_terraform_template(service_name: str, config: CredentialConfig) -> str:
    """Generate Terraform configuration template"""
    return f"""
# IAM user for {config.service_name}
resource "aws_iam_user" "{service_name}_backup" {{
  name = "{service_name}-backup-user"
  path = "/system/"
  
  tags = merge(
    local.common_tags,
    {{
      Name        = "{service_name}-backup-user"
      Application = "{service_name}"
      Purpose     = "s3-backup-access"
    }}
  )
}}

# Create access key for {service_name} user
resource "aws_iam_access_key" "{service_name}_backup" {{
  user = aws_iam_user.{service_name}_backup.name
  
  # Force regeneration of credentials by updating this timestamp
  lifecycle {{
    create_before_destroy = true
  }}
  
  # Keepers to force regeneration when needed
  depends_on = [time_rotating.{service_name}_backup_rotation]
}}

# Time-based rotation trigger for {service_name} backup credentials
resource "time_rotating" "{service_name}_backup_rotation" {{
  # Rotate credentials immediately by setting a past date
  rotation_rfc3339 = "2025-07-19T16:25:00Z"
}}

# IAM policy for {service_name} S3 backup access
resource "aws_iam_policy" "{service_name}_backup_s3_access" {{
  name        = "{service_name}-backup-s3-access"
  path        = "/"
  description = "IAM policy for {service_name} to access S3 backup bucket"
  
  policy = jsonencode({{
    Version = "2012-10-17"
    Statement = [
      {{
        Sid    = "ListBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = module.s3_buckets.bucket_arns["{config.s3_bucket_name}"]
      }},
      {{
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${{module.s3_buckets.bucket_arns["{config.s3_bucket_name}"]}}/*"
      }}
    ]
  }})
  
  tags = merge(
    local.common_tags,
    {{
      Name        = "{service_name}-backup-s3-access"
      Application = "{service_name}"
    }}
  )
}}

# Attach the policy to the {service_name} user
resource "aws_iam_user_policy_attachment" "{service_name}_backup_s3_access" {{
  user       = aws_iam_user.{service_name}_backup.name
  policy_arn = aws_iam_policy.{service_name}_backup_s3_access.arn
}}

# Outputs for {service_name} configuration
output "{service_name}_backup_access_key_id" {{
  description = "Access key ID for {service_name} backup user"
  value       = aws_iam_access_key.{service_name}_backup.id
  sensitive   = true
}}

output "{service_name}_backup_secret_access_key" {{
  description = "Secret access key for {service_name} backup user"
  value       = aws_iam_access_key.{service_name}_backup.secret
  sensitive   = true
}}

output "{service_name}_backup_bucket_name" {{
  description = "S3 bucket name for {service_name} backups"
  value       = module.s3_buckets.bucket_ids["{config.s3_bucket_name}"]
}}

output "{service_name}_backup_bucket_region" {{
  description = "AWS region for {service_name} backup bucket"
  value       = var.aws_region
}}
"""


def generate_s3_bucket_config(service_name: str, config: CredentialConfig) -> str:
    """Generate S3 bucket configuration"""
    return f"""
    # Add this to your s3-buckets.tf file:
    
    {config.s3_bucket_name} = {{
      application = "{service_name}"
      purpose     = "database-backups"  # or appropriate purpose
      lifecycle_rules = [
        {{
          id     = "{service_name}_backup_retention"
          status = "Enabled"
          expiration = {{
            days = 90  # Adjust retention as needed
          }}
          noncurrent_version_expiration = {{
            noncurrent_days = 30
          }}
        }}
      ]
    }}
"""


def interactive_config_generator() -> CredentialConfig:
    """Interactive configuration generator"""
    print_colored("Service Configuration Generator", Colors.BLUE)
    print("=" * 35)

    service_name = input("\nService name (e.g., 'redis', 'mongodb'): ").strip()
    if not service_name:
        raise ValueError("Service name is required")

    service_display = input(
        f"Display name (default: '{service_name.title()} S3 Backup'): "
    ).strip()
    if not service_display:
        service_display = f"{service_name.title()} S3 Backup"

    bucket_name = input(
        f"S3 bucket name (default: '{service_name}-backup-home-ops'): "
    ).strip()
    if not bucket_name:
        bucket_name = f"{service_name}-backup-home-ops"

    vault = input("1Password vault (default: 'Automation'): ").strip()
    if not vault:
        vault = "Automation"

    tags_input = input(f"Tags (default: 'aws,{service_name},s3,backup'): ").strip()
    if not tags_input:
        tags = ["aws", service_name, "s3", "backup"]
    else:
        tags = [tag.strip() for tag in tags_input.split(",")]

    return CredentialConfig(
        service_name=service_display,
        terraform_output_prefix=f"{service_name}_backup",
        onepassword_item_title=f"AWS Access Key - {service_name}-s3-backup - home-ops",
        onepassword_vault=vault,
        tags=tags,
        description=f"AWS IAM credentials for {service_display} access. Managed by Terraform in home-iac repository.",
        s3_bucket_name=bucket_name,
        aws_region="us-west-2",
    )


def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Generate service configuration for credential management"
    )

    parser.add_argument(
        "--interactive",
        "-i",
        action="store_true",
        help="Interactive configuration generator",
    )

    parser.add_argument("--service", help="Service name for template generation")

    args = parser.parse_args()

    try:
        if args.interactive:
            config = interactive_config_generator()
            service_name = config.terraform_output_prefix.replace("_backup", "")

            print_colored(
                f"\n✓ Configuration generated for {service_name}", Colors.GREEN
            )

            # Add to service configs (in memory)
            add_service_config(service_name, config)

            print_colored("\nGenerated Terraform configuration:", Colors.YELLOW)
            print(generate_terraform_template(service_name, config))

            print_colored("\nGenerated S3 bucket configuration:", Colors.YELLOW)
            print(generate_s3_bucket_config(service_name, config))

            print_colored("\nNext steps:", Colors.BLUE)
            print(
                "1. Add the Terraform configuration to environments/dev/s3-iam-access.tf"
            )
            print(
                "2. Add the S3 bucket configuration to environments/dev/s3-buckets.tf"
            )
            print("3. Add the service config to scripts/lib/service_configs.py")
            print(f"4. Run: python3 scripts/update-credentials.py {service_name}")

        elif args.service:
            if args.service in SERVICE_CONFIGS:
                config = SERVICE_CONFIGS[args.service]
                print_colored(f"Configuration for {args.service}:", Colors.BLUE)
                print(f"Service Name: {config.service_name}")
                print(f"Terraform Prefix: {config.terraform_output_prefix}")
                print(f"1Password Item: {config.onepassword_item_title}")
                print(f"Vault: {config.onepassword_vault}")
                print(f"S3 Bucket: {config.s3_bucket_name}")
                print(f"Tags: {', '.join(config.tags)}")
            else:
                print_colored(f"✗ Service '{args.service}' not found", Colors.RED)
                return 1
        else:
            parser.print_help()
            return 1

        return 0

    except KeyboardInterrupt:
        print_colored("\n✗ Operation cancelled by user", Colors.RED)
        return 1
    except Exception as e:
        print_colored(f"✗ Error: {e}", Colors.RED)
        return 1


if __name__ == "__main__":
    sys.exit(main())
