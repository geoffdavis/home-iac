# Outputs for UniFi Networks Module

output "network_ids" {
  description = "Map of network names to network IDs"
  value       = { for k, v in unifi_network.this : k => v.id }
}

output "network_names" {
  description = "Map of network keys to network names"
  value       = { for k, v in unifi_network.this : k => v.name }
}

output "network_purposes" {
  description = "Map of network keys to network purposes"
  value       = { for k, v in unifi_network.this : k => v.purpose }
}

output "network_vlans" {
  description = "Map of network keys to VLAN IDs"
  value       = { for k, v in unifi_network.this : k => v.vlan_id }
}

output "network_subnets" {
  description = "Map of network keys to subnet configurations"
  value       = { for k, v in unifi_network.this : k => v.subnet }
}

output "dhcp_ranges" {
  description = "Map of network keys to DHCP ranges"
  value = {
    for k, v in unifi_network.this : k => {
      enabled = v.dhcp_enabled
      start   = v.dhcp_start
      stop    = v.dhcp_stop
      dns     = v.dhcp_dns
    }
  }
}

output "ipv6_configurations" {
  description = "Map of network keys to IPv6 configurations"
  value = {
    for k, v in unifi_network.this : k => {
      interface_type        = v.ipv6_interface_type
      pd_interface          = v.ipv6_pd_interface
      pd_prefixid           = v.ipv6_pd_prefixid
      pd_start              = v.ipv6_pd_start
      pd_stop               = v.ipv6_pd_stop
      ra_enable             = v.ipv6_ra_enable
      ra_preferred_lifetime = v.ipv6_ra_preferred_lifetime
      ra_valid_lifetime     = v.ipv6_ra_valid_lifetime
    }
  }
}

output "wan_networks" {
  description = "Map of WAN network configurations"
  value = {
    for k, v in unifi_network.this : k => {
      id           = v.id
      name         = v.name
      type         = v.wan_type
      networkgroup = v.wan_networkgroup
      egress_qos   = v.wan_egress_qos
      ingress_qos  = v.wan_ingress_qos
    } if v.purpose == "wan"
  }
}

output "lan_networks" {
  description = "Map of LAN network configurations"
  value = {
    for k, v in unifi_network.this : k => {
      id            = v.id
      name          = v.name
      vlan_id       = v.vlan_id
      subnet        = v.subnet
      dhcp_enabled  = v.dhcp_enabled
      igmp_snooping = v.igmp_snooping
      multicast_dns = v.multicast_dns
    } if v.purpose == "lan"
  }
}

output "vlan_networks" {
  description = "Map of VLAN-only network configurations"
  value = {
    for k, v in unifi_network.this : k => {
      id            = v.id
      name          = v.name
      vlan_id       = v.vlan_id
      subnet        = v.subnet
      dhcp_enabled  = v.dhcp_enabled
      igmp_snooping = v.igmp_snooping
      multicast_dns = v.multicast_dns
    } if v.purpose == "vlan-only"
  }
}

output "network_summary" {
  description = "Summary of all networks created"
  value = {
    total_networks = length(unifi_network.this)
    wan_count      = length(local.wan_networks)
    lan_count      = length(local.lan_networks)
    vlan_count     = length(local.vlan_networks)
    ipv6_count     = length(local.ipv6_networks)
    dhcp_count     = length(local.dhcp_networks)
  }
}