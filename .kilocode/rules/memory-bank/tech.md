# Technology Stack and Development Setup

## Core Technologies

### Infrastructure as Code
- **OpenTofu**: v1.8.8 - Terraform-compatible IaC tool for infrastructure management
- **Terraform Providers**:
  - AWS Provider: ~> 5.0 - AWS resource management
  - UniFi Provider: ~> 0.41.0 - UniFi network device management
  - 1Password Provider: ~> 2.0 - Secure credential retrieval
  - Time Provider: ~> 0.9 - Time-based resource management

### Cloud and Networking
- **AWS Services**:
  - S3: Object storage for backups and state management
  - IAM: Identity and access management
  - DynamoDB: State locking for concurrent access prevention
- **UniFi Network Application**: Network device management at `unifi.home.geoffdavis.com`
- **UniFi UDM Pro**: Core networking hardware with VLAN and BGP capabilities

### Security and Credential Management
- **1Password CLI**: v2.30.3 - Secure credential storage and retrieval
- **1Password Account**: `camiandgeoff.1password.com` - Centralized credential vault

## Development Tools

### Version Management
- **mise**: Runtime version management for consistent tool versions across environments
- **Tool Versions** (managed by mise):
  - OpenTofu: 1.8.8
  - AWS CLI: 2.22.21
  - 1Password CLI: 2.30.3
  - Python: 3.12
  - Node.js: 20.18.0
  - jq: 1.7.1
  - Task: 3.38.0

### Code Quality and Linting
- **TFLint**: v0.50.3 - Terraform/OpenTofu linting
- **Shellcheck**: v0.9.0 - Shell script linting
- **Python Tools**:
  - Ruff: v0.1.9 - Python linting
  - Black: v23.12.1 - Python code formatting

### Task Management
- **Taskfile**: v3.38.0 - Task runner for consistent operations
- **Key Task Categories**:
  - Setup and initialization
  - Infrastructure deployment (plan/apply/destroy)
  - Credential management and rotation
  - Code quality (lint/format/validate)
  - S3 bucket discovery and import
  - State management

## Development Environment Setup

### Prerequisites
1. **mise** installation for tool version management
2. **1Password CLI** configured with account access
3. **AWS CLI** with appropriate permissions
4. **Git** for version control

### Initial Setup Process
1. **Tool Installation**: `./scripts/setup-mise.sh` - Installs mise and all required tools
2. **Environment Configuration**: Copy `.env.example` to `.env` and configure 1Password settings
3. **Credential Verification**: Automated testing of 1Password and AWS access
4. **Infrastructure Initialization**: `task setup` - Complete environment setup

### Configuration Files

#### Environment Configuration
- **`.env`**: Environment variables for 1Password and service configuration
- **`.mise.toml`**: Tool version specifications and PATH configuration
- **`Taskfile.yml`**: Task definitions for all operational workflows

#### Infrastructure Configuration
- **`environments/dev/backend.tf`**: S3 backend configuration with DynamoDB locking
- **`environments/dev/versions.tf`**: Provider version constraints
- **`environments/dev/main.tf`**: Provider configurations and common locals

## State Management

### Backend Configuration
- **Storage**: S3 bucket `opentofu-state-home-iac-078129923125`
- **Locking**: DynamoDB table `opentofu-state-locks-home-iac`
- **Encryption**: AES256 at rest
- **Region**: us-west-2
- **Versioning**: Enabled for state history

### State Security
- Remote state stored in encrypted S3 bucket
- DynamoDB locking prevents concurrent modifications
- State access controlled through AWS IAM policies
- Sensitive values marked appropriately in Terraform

## Credential Management Architecture

### 1Password Integration
- **Vault Structure**: Organized by service type (Private, Automation)
- **Item Naming**: Consistent naming convention for AWS credentials
- **Field Mapping**: Configurable field names for different credential types
- **Automated Rotation**: Python-based credential lifecycle management

### AWS Credential Flow
1. **Retrieval**: 1Password CLI extracts credentials during task execution
2. **Environment Variables**: Temporary AWS credentials set for OpenTofu operations
3. **Rotation**: Automated IAM credential rotation with 1Password updates
4. **Validation**: Credential testing before infrastructure operations

## Automation Framework

### Python Libraries (`scripts/lib/`)
- **`credential_manager.py`**: Core credential management framework
- **`service_configs.py`**: Service-specific configuration definitions
- **Modular Design**: Extensible framework for new services

### Shell Scripts (`scripts/`)
- **`init-setup.sh`**: Initial environment setup and validation
- **`discover-s3-buckets.sh`**: S3 bucket discovery and configuration generation
- **`setup-mise.sh`**: Tool installation and version management
- **Credential Scripts**: Service-specific credential rotation utilities

## Network Architecture Technical Details

### VLAN Configuration
- **Main LAN**: 192.168.1.0/24 (VLAN 1) - Trusted devices
- **Guest Network**: 192.168.10.0/24 (VLAN 10) - Isolated guest access
- **IoT Devices**: 192.168.20.0/24 (VLAN 20) - Smart home devices
- **Management**: 192.168.30.0/24 (VLAN 30) - Infrastructure management
- **Security Cameras**: 192.168.40.0/24 (VLAN 40) - Surveillance systems

### IPv6 Support
- **Prefix Delegation**: Automatic IPv6 prefix assignment from ISP
- **SLAAC**: Stateless Address Autoconfiguration enabled
- **Router Advertisement**: Configured per VLAN with appropriate lifetimes
- **Dual Stack**: Full IPv4/IPv6 dual-stack operation

### WiFi Security Configuration
- **WPA3 Support**: Modern security with backward compatibility
- **PMF (Protected Management Frames)**: Configurable per network type
- **Band Steering**: Automatic optimization between 2.4GHz and 5GHz
- **Fast Roaming**: 802.11r support for seamless handoffs
- **BSS Transition**: 802.11v support for optimal AP selection

## Dependency Management

### Automated Updates
- **Renovate**: Automated dependency updates via GitHub integration
- **Schedule**: Weekly updates on Monday mornings
- **Scope**: OpenTofu providers, mise tools, Python packages
- **Safety**: Patch updates auto-merged, major updates require review

### Version Constraints
- **OpenTofu**: Pinned to specific version for consistency
- **Providers**: Compatible version ranges with automatic updates
- **Tools**: Managed through mise with automatic installation

## Testing and Validation

### Code Quality Checks
- **Pre-commit Hooks**: Automated linting on git commits
- **CI/CD Integration**: Validation pipeline for pull requests
- **Format Validation**: Consistent code formatting across all files
- **Security Scanning**: Credential and configuration validation

### Infrastructure Testing
- **Plan Validation**: Dry-run testing before applying changes
- **State Validation**: Consistency checks between desired and actual state
- **Credential Testing**: Automated validation of credential access
- **Network Validation**: Connectivity and configuration verification

## Monitoring and Observability

### Current Capabilities
- **Task Execution Logging**: Detailed output from all operations
- **Credential Rotation Tracking**: Success/failure monitoring
- **State Change Tracking**: Git-based change history
- **Error Reporting**: Structured error messages with troubleshooting guidance

### Future Enhancements
- **Prometheus Integration**: Infrastructure metrics collection
- **Alerting**: Automated notifications for failures
- **Dashboard**: Visual monitoring of infrastructure health
- **Log Aggregation**: Centralized logging for all operations

## Development Workflow

### Standard Operations
1. **Feature Development**: Branch-based development with PR reviews
2. **Testing**: Local validation with `task lint` and `task validate`
3. **Deployment**: Plan review followed by apply operations
4. **Monitoring**: Post-deployment validation and monitoring

### Emergency Procedures
- **State Recovery**: Backup and restore procedures for state corruption
- **Credential Recovery**: Manual credential rotation procedures
- **Network Recovery**: BGP and routing configuration backup procedures
- **Rollback Procedures**: Infrastructure rollback and recovery processes

## Integration Points

### Sister Repository Integration
- **talos-gitops**: Kubernetes GitOps repository consuming network configurations
- **Shared Resources**: S3 buckets, network VLANs, credential references
- **Coordination**: Synchronized deployments and dependency management

### External Service Integration
- **Home Assistant**: Backup storage consumer with automated credentials
- **Longhorn**: Kubernetes storage backup integration
- **PostgreSQL**: Database backup automation with lifecycle management
- **Monitoring Systems**: Future integration with Prometheus and Grafana