# BGP Configuration Guide for UniFi UDM Pro

**Generated on:** ${timestamp()}  
**Site:** ${site}  
**Configuration Status:** Manual Configuration Required

## ⚠️ Important Notice

**BGP configuration is NOT supported by the UniFi Terraform provider.** This documentation provides guidance for manual configuration through alternative methods.

## Configuration Summary

| Parameter | Value |
|-----------|-------|
| BGP Enabled | ${bgp_config.enabled} |
| AS Number | ${bgp_config.as_number} |
| Router ID | ${bgp_config.router_id} |
| IPv4 Neighbors | ${length(bgp_config.neighbors)} |
| IPv4 Networks | ${length(bgp_config.advertised_networks)} |
| IPv6 Enabled | ${bgp_config.ipv6_enabled} |
| IPv6 Neighbors | ${length(bgp_config.ipv6_neighbors)} |
| IPv6 Networks | ${length(bgp_config.ipv6_networks)} |

## BGP Neighbors Configuration

%{ if length(bgp_config.neighbors) > 0 ~}
### IPv4 BGP Neighbors

| Neighbor IP | Remote AS | Description | Authentication |
|-------------|-----------|-------------|----------------|
%{ for neighbor in bgp_config.neighbors ~}
| ${neighbor.ip} | ${neighbor.remote_as} | ${neighbor.description != "" ? neighbor.description : "N/A"} | ${neighbor.password != null ? "MD5" : "None"} |
%{ endfor ~}

### Neighbor Details

%{ for neighbor in bgp_config.neighbors ~}
#### Neighbor: ${neighbor.ip}
- **Remote AS:** ${neighbor.remote_as}
- **Description:** ${neighbor.description != "" ? neighbor.description : "Not specified"}
- **Authentication:** ${neighbor.password != null ? "MD5 (password configured)" : "None"}
- **Keepalive Timer:** ${neighbor.keepalive_timer} seconds
- **Hold Timer:** ${neighbor.hold_timer} seconds
- **Maximum Prefix:** ${neighbor.maximum_prefix}
%{ if neighbor.route_map_in != null ~}
- **Inbound Route Map:** ${neighbor.route_map_in}
%{ endif ~}
%{ if neighbor.route_map_out != null ~}
- **Outbound Route Map:** ${neighbor.route_map_out}
%{ endif ~}
%{ if neighbor.prefix_list_in != null ~}
- **Inbound Prefix List:** ${neighbor.prefix_list_in}
%{ endif ~}
%{ if neighbor.prefix_list_out != null ~}
- **Outbound Prefix List:** ${neighbor.prefix_list_out}
%{ endif ~}

%{ endfor ~}
%{ else ~}
### IPv4 BGP Neighbors
No IPv4 BGP neighbors configured.
%{ endif ~}

%{ if bgp_config.ipv6_enabled && length(bgp_config.ipv6_neighbors) > 0 ~}
### IPv6 BGP Neighbors

| Neighbor IP | Remote AS | Description | Activated |
|-------------|-----------|-------------|-----------|
%{ for neighbor in bgp_config.ipv6_neighbors ~}
| ${neighbor.ip} | ${neighbor.remote_as} | ${neighbor.description != "" ? neighbor.description : "N/A"} | ${neighbor.activate ? "Yes" : "No"} |
%{ endfor ~}
%{ endif ~}

## Network Advertisements

%{ if length(bgp_config.advertised_networks) > 0 ~}
### IPv4 Networks

| Network | Route Map | Metric |
|---------|-----------|--------|
%{ for network in bgp_config.advertised_networks ~}
| ${network.prefix} | ${network.route_map != null ? network.route_map : "N/A"} | ${network.metric != null ? network.metric : "Default"} |
%{ endfor ~}
%{ else ~}
### IPv4 Networks
No IPv4 networks configured for advertisement.
%{ endif ~}

%{ if bgp_config.ipv6_enabled && length(bgp_config.ipv6_networks) > 0 ~}
### IPv6 Networks

| Network |
|---------|
%{ for network in bgp_config.ipv6_networks ~}
| ${network.prefix} |
%{ endfor ~}
%{ endif ~}

## Route Policies

%{ if length(bgp_config.route_maps) > 0 ~}
### Route Maps

%{ for name, config in bgp_config.route_maps ~}
#### Route Map: ${name}

| Sequence | Action | Match Conditions | Set Actions |
|----------|--------|------------------|-------------|
%{ for rule in config.rules ~}
| ${rule.sequence} | ${rule.action} | ${rule.match_prefix_list != null ? "prefix-list: ${rule.match_prefix_list}" : ""}${rule.match_as_path != null ? " as-path: ${rule.match_as_path}" : ""}${rule.match_community != null ? " community: ${rule.match_community}" : ""} | ${rule.set_local_preference != null ? "local-pref: ${rule.set_local_preference}" : ""}${rule.set_metric != null ? " metric: ${rule.set_metric}" : ""}${rule.set_community != null ? " community: ${rule.set_community}" : ""} |
%{ endfor ~}

%{ endfor ~}
%{ else ~}
### Route Maps
No route maps configured.
%{ endif ~}

%{ if length(bgp_config.prefix_lists) > 0 ~}
### Prefix Lists

%{ for name, config in bgp_config.prefix_lists ~}
#### Prefix List: ${name}

| Sequence | Action | Prefix | GE | LE |
|----------|--------|--------|----|----|
%{ for rule in config.rules ~}
| ${rule.sequence} | ${rule.action} | ${rule.prefix} | ${rule.ge != null ? rule.ge : "N/A"} | ${rule.le != null ? rule.le : "N/A"} |
%{ endfor ~}

%{ endfor ~}
%{ else ~}
### Prefix Lists
No prefix lists configured.
%{ endif ~}

## Manual Configuration Methods

### Method 1: UniFi Network Application

1. **Access the UniFi Network Application:**
   ```
   https://your-udm-pro-ip
   ```

2. **Navigate to BGP Settings:**
   - Go to Settings → Routing & Firewall
   - Look for Advanced Routing or BGP section
   - If BGP options are not visible, they may not be available in your UniFi OS version

3. **Configure Basic BGP Parameters:**
   - AS Number: `${bgp_config.as_number}`
   - Router ID: `${bgp_config.router_id}`

4. **Add BGP Neighbors:**
%{ for neighbor in bgp_config.neighbors ~}
   - Neighbor: `${neighbor.ip}`, Remote AS: `${neighbor.remote_as}`
%{ endfor ~}

5. **Configure Network Advertisements:**
%{ for network in bgp_config.advertised_networks ~}
   - Network: `${network.prefix}`
%{ endfor ~}

### Method 2: SSH Configuration

**⚠️ Warning:** SSH configuration commands may vary based on UniFi OS version.

1. **SSH into UDM Pro:**
   ```bash
   ssh root@your-udm-pro-ip
   ```

2. **Enter configuration mode:**
   ```bash
   configure
   ```

3. **Configure BGP:**
   ```bash
   set protocols bgp ${bgp_config.as_number}
   set protocols bgp ${bgp_config.as_number} parameters router-id ${bgp_config.router_id}
   ```

4. **Configure neighbors:**
%{ for neighbor in bgp_config.neighbors ~}
   ```bash
   set protocols bgp ${bgp_config.as_number} neighbor ${neighbor.ip} remote-as ${neighbor.remote_as}
%{ if neighbor.description != "" ~}
   set protocols bgp ${bgp_config.as_number} neighbor ${neighbor.ip} description "${neighbor.description}"
%{ endif ~}
%{ if neighbor.password != null ~}
   set protocols bgp ${bgp_config.as_number} neighbor ${neighbor.ip} password "${neighbor.password}"
%{ endif ~}
   ```
%{ endfor ~}

5. **Advertise networks:**
%{ for network in bgp_config.advertised_networks ~}
   ```bash
   set protocols bgp ${bgp_config.as_number} network ${network.prefix}
   ```
%{ endfor ~}

6. **Commit and save:**
   ```bash
   commit
   save
   exit
   ```

### Method 3: Configuration Management

Consider using configuration management tools like Ansible, Puppet, or Chef to automate BGP configuration:

```yaml
# Example Ansible playbook structure
- name: Configure BGP on UDM Pro
  hosts: udm_pro
  tasks:
    - name: Configure BGP AS number
      # Custom module or shell commands
    - name: Configure BGP neighbors
      # Iterate through neighbor list
    - name: Configure network advertisements
      # Configure advertised networks
```

## Validation and Monitoring

### BGP Status Commands

After configuration, verify BGP status using these commands (via SSH):

```bash
# Show BGP summary
show ip bgp summary

# Show BGP neighbors
show ip bgp neighbors

# Show BGP routes
show ip route bgp

# Show specific neighbor details
show ip bgp neighbors <neighbor-ip>
```

### Monitoring Checklist

- [ ] BGP neighbors are in "Established" state
- [ ] Expected routes are being received and advertised
- [ ] Route filtering is working correctly
- [ ] No route leaks or unexpected advertisements
- [ ] BGP authentication is functioning (if configured)

## Security Considerations

### BGP Security Best Practices

1. **Authentication:**
   - Use MD5 authentication for all BGP sessions
   - Regularly rotate BGP passwords

2. **Route Filtering:**
   - Implement strict inbound and outbound route filters
   - Use prefix lists to control route advertisements
   - Configure maximum prefix limits

3. **AS Path Filtering:**
   - Filter routes based on AS path patterns
   - Prevent AS path manipulation attacks

4. **Network Segmentation:**
   - Ensure BGP configuration aligns with network security policies
   - Implement proper firewall rules for BGP traffic (TCP port 179)

## Troubleshooting

### Common Issues

1. **Neighbor Not Establishing:**
   - Check network connectivity
   - Verify AS numbers
   - Check authentication configuration
   - Review firewall rules

2. **Routes Not Being Advertised:**
   - Verify network statements
   - Check route maps and filters
   - Ensure networks exist in routing table

3. **Unexpected Route Selection:**
   - Review BGP path selection algorithm
   - Check local preference and MED values
   - Verify AS path lengths

### Debug Commands

```bash
# Enable BGP debugging (use with caution in production)
debug ip bgp
debug ip bgp events
debug ip bgp updates

# Disable debugging
no debug all
```

## Integration with Existing Infrastructure

### UniFi Network Compatibility

Ensure BGP configuration is compatible with existing UniFi network setup:

- **VLANs:** Verify advertised networks don't conflict with VLAN subnets
- **Firewall Rules:** Update firewall rules to accommodate BGP traffic
- **DHCP:** Ensure DHCP scopes don't overlap with BGP routes
- **DNS:** Consider DNS implications of route advertisements

### Terraform Integration Status

| Component | Status | Notes |
|-----------|--------|-------|
| UniFi Provider | v0.41.0 | No BGP support |
| BGP Resources | Not Available | Manual configuration required |
| Future Support | Unknown | Monitor provider releases |

## Future Migration Path

When BGP support becomes available in the UniFi Terraform provider:

1. **Import existing configuration:**
   ```bash
   terraform import unifi_bgp.main <bgp-id>
   ```

2. **Convert to Terraform:**
   - Move configuration from manual to Terraform resources
   - Update variable definitions
   - Test configuration changes

3. **Validate migration:**
   - Ensure no service disruption
   - Verify all BGP sessions remain stable
   - Confirm route advertisements are unchanged

## Support and Documentation

### Additional Resources

- [UniFi Documentation](https://help.ui.com/)
- [BGP RFC 4271](https://tools.ietf.org/html/rfc4271)
- [BGP Security Best Practices](https://tools.ietf.org/html/rfc7454)

### Getting Help

1. **UniFi Community Forums**
2. **UniFi Support Portal**
3. **Network Engineering Communities**
4. **BGP Configuration Guides**

---

**Generated by:** Terraform UniFi BGP Module  
**Last Updated:** ${timestamp()}  
**Configuration File:** This document is automatically generated and should be updated through Terraform variables.