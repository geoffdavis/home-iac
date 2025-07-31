# Home Infrastructure as Code - Product Definition

## Project Purpose

This project provides Infrastructure as Code (IaC) management for a comprehensive home network and cloud infrastructure using OpenTofu (Terraform-compatible). It serves as the central configuration management system for both on-premises UniFi networking equipment and AWS cloud resources that support home operations.

## Problems It Solves

### Infrastructure Management Challenges
- **Manual Configuration Drift**: Eliminates inconsistent manual configuration of network devices and cloud resources
- **Credential Management**: Provides secure, automated credential rotation and storage using 1Password integration
- **Backup Infrastructure**: Ensures reliable, automated backup systems for critical home services
- **Network Segmentation**: Implements proper VLAN-based network isolation for security and performance
- **State Management**: Maintains infrastructure state with proper locking and versioning

### Home Operations Support
- **Home Assistant Backups**: Automated S3-based backup storage for Home Assistant configurations
- **Kubernetes Storage**: Longhorn backup integration for home Kubernetes cluster persistent volumes
- **Database Backups**: PostgreSQL backup automation for various home services
- **Network Security**: Proper WiFi segmentation for IoT devices, guests, and trusted devices

## How It Should Work

### Core Workflow
1. **Declarative Configuration**: All infrastructure defined in version-controlled OpenTofu files
2. **Secure Credential Management**: AWS credentials stored in 1Password, automatically retrieved during operations
3. **Automated Deployment**: Task-based workflow using Taskfile for consistent operations
4. **State Synchronization**: Remote state storage in S3 with DynamoDB locking
5. **Dependency Management**: Automated tool version management using mise

### Network Architecture
- **Segmented VLANs**: Separate networks for main LAN, guest access, IoT devices, management, and security cameras
- **WiFi Management**: Multiple SSIDs with appropriate security settings for different device types
- **IPv6 Support**: Full IPv6 configuration with prefix delegation
- **BGP Documentation**: Comprehensive BGP configuration documentation (manual implementation required)

### Cloud Integration
- **S3 Bucket Management**: Automated creation and configuration of backup storage buckets
- **IAM Access Control**: Proper permissions for service accounts accessing S3 resources
- **Lifecycle Management**: Automated data retention policies for cost optimization

## User Experience Goals

### Developer Experience
- **Simple Setup**: One-command initialization with `task setup`
- **Clear Documentation**: Comprehensive guides for setup, operation, and troubleshooting
- **Consistent Operations**: Standardized commands for all infrastructure operations
- **Safe Changes**: Plan-before-apply workflow with proper validation

### Operational Excellence
- **Reliable Backups**: Automated, tested backup systems for all critical data
- **Security First**: Proper network segmentation and credential management
- **Cost Optimization**: Lifecycle rules and resource tagging for cost control
- **Monitoring Ready**: Infrastructure configured for easy integration with monitoring systems

### Maintenance Efficiency
- **Automated Updates**: Renovate integration for dependency management
- **Credential Rotation**: Automated AWS credential rotation with 1Password updates
- **Configuration Validation**: Linting and validation in CI/CD pipeline
- **Documentation Generation**: Automated documentation updates from configuration

## Success Metrics

### Infrastructure Reliability
- Zero manual configuration drift
- 100% backup success rate for critical services
- Proper network isolation between VLANs
- Automated credential rotation without service interruption

### Developer Productivity
- Sub-5-minute setup time for new environments
- Single-command deployment and rollback
- Clear error messages and troubleshooting guides
- Comprehensive test coverage for infrastructure changes

### Security Posture
- All credentials stored securely in 1Password
- Network traffic properly segmented by device type
- Regular security updates through automated dependency management
- Audit trail for all infrastructure changes

## Integration Points

### Sister Repository
- **talos-gitops**: Consumes network and storage configurations from this repository
- **Location**: `../talos-gitops` (typically checked out alongside this repo)
- **Dependencies**: S3 bucket configurations, network VLAN definitions, credential references

### External Services
- **1Password**: Secure credential storage and retrieval
- **AWS**: Cloud storage and IAM management
- **UniFi Controller**: Network device configuration
- **Home Assistant**: Backup storage consumer
- **Longhorn**: Kubernetes storage backup consumer
- **PostgreSQL**: Database backup storage consumer

## Future Enhancements

### Planned Features
- **BGP Provider Support**: When UniFi Terraform provider adds BGP resources
- **Multi-Environment**: Production/staging environment separation
- **Monitoring Integration**: Prometheus metrics and alerting
- **Automated Testing**: Infrastructure testing with Terratest

### Scalability Considerations
- **Multi-Site Support**: Extension to multiple physical locations
- **Cloud Provider Diversity**: Support for additional cloud providers
- **Service Mesh Integration**: Advanced networking for Kubernetes workloads
- **GitOps Integration**: Full GitOps workflow with ArgoCD or Flux