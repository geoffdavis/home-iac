# UniFi BGP Configuration Module

## Overview

This module documents BGP configuration requirements for UniFi UDM Pro devices. **Important**: BGP configuration is not currently supported by the UniFi Terraform provider and must be configured manually through the UniFi Network Application or SSH.

## Current Limitations

### UniFi Terraform Provider Limitations
- No dedicated BGP resources available
- No routing protocol configuration support in `unifi_network` resource
- No advanced routing features in `unifi_device` resource
- Provider focuses on basic network, WLAN, firewall, and device management

### Research Summary
Based on comprehensive research of the UniFi Terraform provider (v0.41.0):
- **Available Resources**: `unifi_network`, `unifi_device`, `unifi_firewall_rule`, `unifi_wlan`, etc.
- **Missing Resources**: No BGP, OSPF, or other routing protocol resources
- **Provider Scope**: Limited to basic UniFi controller API functionality
- **GitHub Analysis**: No BGP-related code, issues, or feature requests found

## Manual BGP Configuration Required

### UDM Pro BGP Capabilities
The UniFi Dream Machine Pro supports BGP through:
1. **UniFi Network Application**: Advanced routing features (if available)
2. **SSH Access**: Direct configuration via command line
3. **JSON Configuration**: Advanced settings through controller API

### Manual Configuration Steps

#### Option 1: UniFi Network Application
1. Access UniFi Network Application
2. Navigate to Settings → Routing & Firewall
3. Look for Advanced Routing or BGP settings
4. Configure BGP parameters manually

#### Option 2: SSH Configuration
```bash
# SSH into UDM Pro
ssh root@<udm-pro-ip>

# Access UniFi OS shell
unifi-os shell

# Configure BGP (example - actual commands may vary)
# Note: Specific BGP configuration commands depend on UniFi OS version
```

#### Option 3: Controller API
```bash
# Use UniFi Controller API for advanced configuration
# This requires direct API calls outside of Terraform
curl -X POST "https://<controller>/api/s/default/rest/routing" \
  -H "Content-Type: application/json" \
  -d '{"bgp_config": {...}}'
```

## Recommended Implementation Approach

### 1. Terraform-Managed Infrastructure
Use this project's existing modules for:
- Network/VLAN configuration (`unifi-networks`)
- WiFi/WLAN setup (`unifi-wlans`)
- Basic device management
- Firewall rules

### 2. External BGP Configuration
Implement BGP configuration through:
- **Configuration Management**: Ansible, Chef, or Puppet
- **Custom Scripts**: Shell scripts for SSH-based configuration
- **Documentation**: Detailed manual configuration procedures

### 3. Hybrid Approach
```hcl
# Terraform manages basic infrastructure
module "unifi_networks" {
  source = "../../modules/unifi-networks"
  # ... network configuration
}

# External process handles BGP
# - Manual configuration
# - Configuration management tools
# - Custom automation scripts
```

## BGP Configuration Template

### Typical BGP Parameters Needed
```yaml
bgp_config:
  as_number: 65001
  router_id: "192.168.1.1"
  neighbors:
    - ip: "192.168.1.2"
      remote_as: 65002
      description: "ISP Connection"
    - ip: "192.168.1.3"
      remote_as: 65003
      description: "Peer Connection"
  networks:
    - "192.168.0.0/16"
    - "10.0.0.0/8"
  route_maps:
    - name: "ALLOW_LOCAL"
      action: "permit"
      prefix_list: "LOCAL_NETWORKS"
```

### IPv6 BGP Configuration
```yaml
bgp_ipv6_config:
  address_family: "ipv6"
  neighbors:
    - ip: "2001:db8::1"
      remote_as: 65002
      activate: true
  networks:
    - "2001:db8::/32"
```

## Future Enhancements

### Provider Enhancement Opportunities
1. **Feature Request**: Submit BGP support request to UniFi provider
2. **Community Contribution**: Develop BGP resource for provider
3. **Alternative Providers**: Explore other UniFi management tools

### Migration Path
When BGP support becomes available:
1. Convert manual configuration to Terraform resources
2. Import existing BGP configuration
3. Integrate with existing network modules

## Monitoring and Validation

### BGP Status Verification
```bash
# Check BGP status (example commands)
show ip bgp summary
show ip bgp neighbors
show ip route bgp
```

### Integration with Existing Monitoring
- Include BGP metrics in network monitoring
- Alert on BGP neighbor state changes
- Monitor route advertisements

## Security Considerations

### BGP Security Best Practices
- Use BGP authentication (MD5 or TCP-AO)
- Implement route filtering
- Configure maximum prefix limits
- Use private AS numbers appropriately

### Network Segmentation
- Ensure BGP configuration aligns with VLAN design
- Implement proper firewall rules for BGP traffic
- Consider route leak prevention

## Documentation Requirements

### Configuration Documentation
- Document all BGP neighbors and their purposes
- Maintain route map and filter configurations
- Record AS number assignments and justifications

### Change Management
- Version control BGP configuration changes
- Test BGP changes in development environment
- Maintain rollback procedures

## Support and Troubleshooting

### Common Issues
1. **Neighbor Establishment**: Check connectivity and authentication
2. **Route Advertisement**: Verify network statements and route maps
3. **Path Selection**: Understand BGP path selection algorithm

### Debugging Tools
- BGP debug commands
- Packet captures for BGP traffic
- Route table analysis

## Conclusion

While BGP configuration cannot be managed through Terraform with the current UniFi provider, this documentation provides a framework for manual configuration and future automation. The hybrid approach allows Terraform to manage supported infrastructure while BGP is configured through alternative methods.

For immediate BGP implementation, manual configuration through the UniFi Network Application or SSH is required. Future provider enhancements may enable full Terraform management of BGP configuration.