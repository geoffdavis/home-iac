# UniFi BGP Configuration Limitations and Manual Steps

## Overview

This document outlines the current limitations of BGP configuration management through the UniFi Terraform provider and provides detailed manual configuration steps required for implementing BGP on UniFi UDM Pro devices.

## Current Provider Limitations

### UniFi Terraform Provider Analysis (v0.41.0)

**Research Conducted:** January 24, 2025

#### Available Resources
- ✅ `unifi_network` - Network/VLAN configuration
- ✅ `unifi_device` - Basic device management
- ✅ `unifi_wlan` - WiFi/WLAN configuration
- ✅ `unifi_firewall_rule` - Firewall rules
- ✅ `unifi_port_forward` - Port forwarding
- ✅ `unifi_dns_record` - DNS records
- ✅ `unifi_account` - User accounts

#### Missing BGP Resources
- ❌ `unifi_bgp` - BGP configuration
- ❌ `unifi_routing` - Advanced routing protocols
- ❌ `unifi_route_map` - Route filtering policies
- ❌ `unifi_prefix_list` - Prefix list management
- ❌ `unifi_as_path_list` - AS path filtering

#### Provider Scope Analysis
The UniFi Terraform provider is focused on:
- Basic network infrastructure (VLANs, WiFi)
- Device adoption and management
- Firewall and security policies
- User and access management

**BGP and advanced routing protocols are outside the current provider scope.**

### GitHub Repository Analysis

**Repository:** `ubiquiti-community/terraform-provider-unifi`

#### Code Search Results
- **BGP-related files:** None found
- **Routing protocol files:** None found
- **Feature requests:** No BGP-related issues or discussions
- **Community interest:** No evidence of BGP support requests

#### Provider Architecture
The provider is built around the UniFi Controller API, which primarily exposes:
- Network management endpoints
- Device configuration endpoints
- Security policy endpoints

**Advanced routing configuration is not exposed through the standard UniFi Controller API.**

## Manual Configuration Requirements

### Prerequisites

1. **UniFi UDM Pro Device**
   - UniFi OS version with BGP support
   - Administrative access to device
   - Network connectivity for BGP neighbors

2. **Access Methods**
   - UniFi Network Application (web interface)
   - SSH access to UDM Pro
   - UniFi Controller API (advanced)

3. **Network Planning**
   - AS number assignment
   - BGP neighbor information
   - Route advertisement strategy
   - Security and filtering policies

### Configuration Methods

#### Method 1: UniFi Network Application (Recommended)

**Availability:** Depends on UniFi OS version and feature availability

1. **Access the Interface:**
   ```
   https://your-udm-pro-ip
   ```

2. **Navigate to Routing Settings:**
   - Settings → Routing & Firewall
   - Advanced Routing (if available)
   - BGP Configuration section

3. **Configure Basic Parameters:**
   - AS Number
   - Router ID
   - BGP neighbors
   - Network advertisements

**Limitations:**
- BGP features may not be available in all UniFi OS versions
- Limited advanced configuration options
- UI-based configuration only

#### Method 2: SSH Configuration (Advanced)

**Requirements:**
- SSH access enabled on UDM Pro
- Root or administrative privileges
- Knowledge of UniFi OS command structure

**Configuration Steps:**

1. **SSH Access:**
   ```bash
   ssh root@udm-pro-ip
   ```

2. **Enter Configuration Mode:**
   ```bash
   configure
   ```

3. **Basic BGP Configuration:**
   ```bash
   set protocols bgp [AS-NUMBER]
   set protocols bgp [AS-NUMBER] parameters router-id [ROUTER-ID]
   ```

4. **Neighbor Configuration:**
   ```bash
   set protocols bgp [AS-NUMBER] neighbor [NEIGHBOR-IP] remote-as [REMOTE-AS]
   set protocols bgp [AS-NUMBER] neighbor [NEIGHBOR-IP] description "[DESCRIPTION]"
   ```

5. **Network Advertisement:**
   ```bash
   set protocols bgp [AS-NUMBER] network [NETWORK/MASK]
   ```

6. **Commit Changes:**
   ```bash
   commit
   save
   exit
   ```

**Important Notes:**
- Commands may vary based on UniFi OS version
- Configuration syntax may differ from standard Vyatta/VyOS
- Always test in development environment first

#### Method 3: API Configuration (Expert Level)

**Requirements:**
- Direct API access to UniFi Controller
- API authentication tokens
- Understanding of UniFi API structure

**Approach:**
- Reverse engineer UniFi Controller API
- Identify routing configuration endpoints
- Implement custom API calls for BGP configuration

**Risks:**
- Unsupported API usage
- Configuration may not persist across updates
- Limited documentation available

### Configuration Management Integration

#### Ansible Integration

```yaml
---
- name: Configure BGP on UDM Pro
  hosts: udm_pro
  tasks:
    - name: Configure BGP AS number
      shell: |
        configure
        set protocols bgp {{ bgp_as_number }}
        set protocols bgp {{ bgp_as_number }} parameters router-id {{ bgp_router_id }}
        commit
        save
        exit
      
    - name: Configure BGP neighbors
      shell: |
        configure
        set protocols bgp {{ bgp_as_number }} neighbor {{ item.ip }} remote-as {{ item.remote_as }}
        set protocols bgp {{ bgp_as_number }} neighbor {{ item.ip }} description "{{ item.description }}"
        commit
        save
        exit
      loop: "{{ bgp_neighbors }}"
```

#### Puppet/Chef Integration

Similar configuration management approaches can be implemented using:
- Puppet exec resources
- Chef execute resources
- Custom providers for UniFi device management

### Validation and Monitoring

#### BGP Status Verification

**SSH Commands:**
```bash
# BGP summary
show ip bgp summary

# BGP neighbors
show ip bgp neighbors

# BGP routes
show ip route bgp

# Specific neighbor details
show ip bgp neighbors [neighbor-ip]
```

#### Monitoring Integration

**Metrics to Monitor:**
- BGP neighbor states
- Route advertisements/withdrawals
- BGP session uptime
- Route table size

**Tools:**
- SNMP monitoring
- Custom scripts for BGP status
- Network monitoring systems (Nagios, Zabbix)

## Security Considerations

### BGP Security Best Practices

1. **Authentication:**
   - Use MD5 authentication for all BGP sessions
   - Implement strong, unique passwords
   - Regular password rotation

2. **Route Filtering:**
   - Implement strict prefix lists
   - Use route maps for policy control
   - Configure maximum prefix limits

3. **Network Segmentation:**
   - Align BGP configuration with network security policies
   - Implement proper firewall rules for BGP traffic
   - Consider route leak prevention

### Firewall Configuration

**Required Rules:**
```bash
# Allow BGP traffic (TCP port 179)
set firewall name WAN_IN rule 100 action accept
set firewall name WAN_IN rule 100 protocol tcp
set firewall name WAN_IN rule 100 destination port 179
set firewall name WAN_IN rule 100 source address [BGP-NEIGHBOR-IP]
```

## Troubleshooting Guide

### Common Issues

1. **BGP Neighbor Not Establishing**
   - Check network connectivity
   - Verify AS numbers
   - Confirm authentication settings
   - Review firewall rules

2. **Routes Not Being Advertised**
   - Verify network statements
   - Check route maps and filters
   - Ensure networks exist in routing table
   - Review BGP synchronization settings

3. **Unexpected Route Selection**
   - Understand BGP path selection algorithm
   - Check local preference values
   - Review MED (metric) settings
   - Verify AS path lengths

### Debug Commands

```bash
# Enable BGP debugging (use with caution)
debug ip bgp
debug ip bgp events
debug ip bgp updates

# Disable debugging
no debug all
```

### Log Analysis

**Log Locations:**
- System logs: `/var/log/messages`
- BGP-specific logs: Check UniFi OS documentation

## Future Migration Strategy

### When Provider Support Becomes Available

1. **Preparation Steps:**
   - Document current manual configuration
   - Create Terraform variable definitions
   - Plan resource import strategy

2. **Migration Process:**
   ```bash
   # Import existing BGP configuration
   terraform import unifi_bgp.main [bgp-resource-id]
   
   # Validate imported configuration
   terraform plan
   
   # Apply any necessary changes
   terraform apply
   ```

3. **Validation:**
   - Ensure no service disruption
   - Verify all BGP sessions remain stable
   - Confirm route advertisements unchanged

### Provider Enhancement Opportunities

1. **Community Contribution:**
   - Develop BGP resources for the provider
   - Submit pull requests to the community
   - Participate in provider development

2. **Feature Requests:**
   - Submit detailed feature requests
   - Provide use cases and requirements
   - Engage with provider maintainers

## Alternative Solutions

### Third-Party Tools

1. **Network Automation Platforms:**
   - Napalm (Network Automation and Programmability Abstraction Layer)
   - Netmiko for device connectivity
   - Custom Python scripts

2. **Configuration Management:**
   - Ansible network modules
   - Puppet network device support
   - Chef network cookbook

3. **API-Based Solutions:**
   - Custom UniFi API integration
   - REST API automation scripts
   - GraphQL-based configuration tools

### Hybrid Approaches

**Recommended Strategy:**
- Use Terraform for supported UniFi resources (networks, WiFi, firewall)
- Use configuration management for BGP configuration
- Implement monitoring and validation scripts
- Plan for future Terraform integration

## Documentation and Change Management

### Configuration Documentation

**Required Documentation:**
- BGP neighbor relationships and purposes
- Route advertisement policies
- Authentication credentials (securely stored)
- Network topology diagrams
- Change history and rationale

### Change Management Process

1. **Development Testing:**
   - Test all BGP changes in lab environment
   - Validate neighbor establishment
   - Verify route advertisements

2. **Production Deployment:**
   - Schedule maintenance windows
   - Implement changes incrementally
   - Monitor BGP sessions continuously
   - Maintain rollback procedures

3. **Post-Implementation:**
   - Validate BGP neighbor states
   - Confirm route table accuracy
   - Update documentation
   - Review monitoring alerts

## Conclusion

While BGP configuration cannot currently be managed through the UniFi Terraform provider, this comprehensive approach provides:

1. **Clear understanding** of current limitations
2. **Multiple configuration methods** for different skill levels
3. **Security best practices** for BGP implementation
4. **Integration strategies** with existing tools
5. **Future migration path** when provider support becomes available

The hybrid approach of using Terraform for supported infrastructure and manual/automated configuration for BGP provides a practical solution while maintaining infrastructure as code principles where possible.

---

**Document Version:** 1.0  
**Last Updated:** January 24, 2025  
**Next Review:** When UniFi provider updates are released