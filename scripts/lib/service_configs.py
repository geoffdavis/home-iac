#!/usr/bin/env python3
"""
Service Configuration Definitions
Defines credential configurations for different services
"""

from credential_manager import CredentialConfig


# Service configurations
SERVICE_CONFIGS = {
    "postgresql": CredentialConfig(
        service_name="PostgreSQL S3 Backup",
        terraform_output_prefix="postgresql_backup",
        onepassword_item_title="AWS Access Key - postgresql-s3-backup - home-ops",
        onepassword_vault="Automation",
        tags=["aws", "postgresql", "s3", "backup", "database"],
        description="AWS IAM credentials for PostgreSQL S3 backup access. Managed by Terraform in home-iac repository.",
        s3_bucket_name="postgresql-backup-home-ops",
        aws_region="us-west-2",
    ),
    "longhorn": CredentialConfig(
        service_name="Longhorn S3 Backup",
        terraform_output_prefix="longhorn_backup",
        onepassword_item_title="AWS Access Key - longhorn-s3-backup - home-ops",
        onepassword_vault="Automation",
        tags=["aws", "longhorn", "s3", "backup", "kubernetes"],
        description="AWS IAM credentials for Longhorn S3 backup access. Managed by Terraform in home-iac repository.",
        s3_bucket_name="longhorn-backups-home-ops",
        aws_region="us-west-2",
    ),
    "home-assistant-postgres": CredentialConfig(
        service_name="Home Assistant PostgreSQL S3 Backup",
        terraform_output_prefix="home_assistant_postgres_backup",
        onepassword_item_title="AWS Access Key - home-assistant-postgres-s3-backup - home-ops",
        onepassword_vault="Automation",
        tags=["aws", "home-assistant", "postgresql", "s3", "backup", "database"],
        description="AWS IAM credentials for Home Assistant PostgreSQL S3 backup access. Managed by Terraform in home-iac repository.",
        s3_bucket_name="home-assistant-postgres-backup-home-ops",
        aws_region="us-west-2",
    ),
    "unifi": CredentialConfig(
        service_name="UniFi Controller API",
        terraform_output_prefix="unifi_api",  # Not used for UniFi (no Terraform outputs)
        onepassword_item_title="Home-ops Unifi API",
        onepassword_vault="Automation",
        tags=["unifi", "api", "network", "controller"],
        description="UniFi Controller API credentials for network management. Used by Terraform UniFi provider.",
        s3_bucket_name=None,  # Not applicable for UniFi
        aws_region="us-west-2",  # Not applicable but required by dataclass
    ),
    # Template for adding new services
    "template": CredentialConfig(
        service_name="Service Name",
        terraform_output_prefix="service_backup",  # Matches Terraform output prefix
        onepassword_item_title="AWS Access Key - service-s3-backup - home-ops",
        onepassword_vault="Automation",
        tags=["aws", "service", "s3", "backup"],
        description="AWS IAM credentials for Service S3 backup access. Managed by Terraform in home-iac repository.",
        s3_bucket_name="service-backup-home-ops",
        aws_region="us-west-2",
    ),
}


def get_service_config(service_name: str) -> CredentialConfig:
    """Get configuration for a specific service"""
    if service_name not in SERVICE_CONFIGS:
        available = ", ".join(SERVICE_CONFIGS.keys())
        raise ValueError(f"Unknown service '{service_name}'. Available: {available}")

    return SERVICE_CONFIGS[service_name]


def list_available_services() -> list:
    """List all available service configurations"""
    return [name for name in SERVICE_CONFIGS.keys() if name != "template"]


def add_service_config(name: str, config: CredentialConfig) -> None:
    """Add a new service configuration"""
    SERVICE_CONFIGS[name] = config
