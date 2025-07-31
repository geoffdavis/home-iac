# Current Context

## Project Status
The home-iac project is in active development and operational use. The infrastructure is currently managing both UniFi networking equipment and AWS S3 storage resources for home operations.

## Current Work Focus
- **Network Infrastructure**: Complete UniFi network and WLAN configuration with comprehensive VLAN segmentation
- **Storage Management**: S3 bucket management for backup systems (Home Assistant, Longhorn, PostgreSQL)
- **Credential Management**: 1Password integration for secure credential storage and rotation
- **BGP Documentation**: Comprehensive BGP configuration documentation (awaiting provider support)

## Recent Changes
- Implemented comprehensive UniFi network module with IPv6 support and VLAN segmentation
- Created detailed WLAN configurations for different device types and security levels
- Established S3 bucket management for multiple backup services
- Developed credential rotation system with 1Password integration
- Added BGP configuration documentation module (placeholder for future implementation)
- **Added Home Assistant PostgreSQL backup infrastructure** with dedicated S3 bucket and IAM credentials
- Enhanced credential management framework with home-assistant-postgres service configuration
- Integrated Cloud-Native PostgreSQL backup support with comprehensive task automation

## Current Infrastructure State

### Network Configuration
- **Main LAN**: 192.168.1.0/24 (VLAN 1) with IPv6 prefix delegation
- **Guest Network**: 192.168.10.0/24 (VLAN 10) with isolation
- **IoT Devices**: 192.168.20.0/24 (VLAN 20) for smart home devices
- **Management**: 192.168.30.0/24 (VLAN 30) for infrastructure management
- **Security Cameras**: 192.168.40.0/24 (VLAN 40) for surveillance systems

### WiFi Networks
- **HomeNetwork**: Main trusted network (WPA3 with transition)
- **HomeGuest**: Guest access with isolation
- **HomeIoT**: Hidden IoT network with legacy compatibility
- **HomeMgmt**: Hidden management network with MAC filtering
- **HomePerformance**: 5GHz-only high-performance network
- **HomeLegacy**: 2.4GHz-only for legacy devices

### S3 Storage
- **home-assistant-backups-hassio-pi**: Home Assistant backup storage
- **longhorn-backups-home-ops**: Kubernetes persistent volume backups
- **postgresql-backup-home-ops**: PostgreSQL database backups with lifecycle rules
- **home-assistant-postgres-backup-home-ops**: Home Assistant PostgreSQL database backups (Cloud-Native PostgreSQL)

## Active Development Areas

### Immediate Priorities
1. **BGP Implementation**: Waiting for UniFi Terraform provider BGP support
2. **Monitoring Integration**: Adding infrastructure monitoring and alerting
3. **Multi-Environment Support**: Separating dev/staging/production configurations
4. **Automated Testing**: Infrastructure validation and testing framework

### Technical Debt
- BGP configuration currently requires manual implementation
- Some credential rotation processes need automation improvements
- Documentation could be enhanced with more examples

## Integration Status

### Sister Repository (talos-gitops)
- **Status**: Active integration
- **Location**: `../talos-gitops`
- **Dependencies**: Network configurations, S3 bucket references, credential management

### External Services
- **1Password**: Fully integrated for credential management
- **AWS**: Active S3 and IAM management
- **UniFi Controller**: Network and WLAN management operational
- **Home Assistant**: Consuming backup storage (file backups and PostgreSQL database backups)
- **Longhorn**: Kubernetes storage backup integration
- **PostgreSQL**: Database backup automation (standalone and Cloud-Native PostgreSQL)
- **Cloud-Native PostgreSQL**: Kubernetes-native PostgreSQL operator with S3 backup integration

## Next Steps
1. Monitor for UniFi Terraform provider BGP support updates
2. Implement comprehensive infrastructure monitoring
3. Add automated testing for infrastructure changes
4. Enhance documentation with more operational examples
5. Consider multi-site support for future expansion

## Known Issues
- BGP configuration requires manual implementation due to provider limitations
- Some legacy IoT devices may need specific compatibility adjustments
- Credential rotation timing could be optimized for better automation

## Environment Details
- **Primary Environment**: Development (dev)
- **State Storage**: S3 with DynamoDB locking
- **Tool Management**: mise for consistent tool versions
- **Task Management**: Taskfile for operational workflows