# UniFi Networks Module - Main Configuration

# UniFi Network Resources
resource "unifi_network" "this" {
  for_each = var.networks

  name    = each.value.name
  purpose = each.value.purpose
  site    = coalesce(each.value.site, var.site)

  # VLAN Configuration
  vlan_id = each.value.vlan_id

  # Subnet Configuration
  subnet = each.value.subnet

  # DHCP Configuration
  dhcp_enabled    = each.value.dhcp_enabled
  dhcp_start      = each.value.dhcp_start
  dhcp_stop       = each.value.dhcp_stop
  dhcp_dns        = coalesce(each.value.dhcp_dns, var.default_dns_servers)
  dhcp_lease_time = each.value.dhcp_lease_time
  domain_name     = coalesce(each.value.domain_name, var.default_domain_name)

  # Network Features
  igmp_snooping = each.value.igmp_snooping
  multicast_dns = each.value.multicast_dns

  # WAN Configuration (for WAN networks)
  wan_networkgroup = each.value.wan_networkgroup
  wan_type         = each.value.wan_type
  wan_ip           = each.value.wan_ip
  wan_netmask      = each.value.wan_netmask
  wan_gateway      = each.value.wan_gateway
  wan_dns          = each.value.wan_dns
  wan_username     = each.value.wan_username
  wan_password     = each.value.wan_password
  wan_egress_qos   = each.value.wan_egress_qos
  wan_ingress_qos  = each.value.wan_ingress_qos

  # IPv6 Configuration
  ipv6_interface_type        = each.value.ipv6_interface_type
  ipv6_pd_interface          = each.value.ipv6_pd_interface
  ipv6_pd_prefixid           = each.value.ipv6_pd_prefixid
  ipv6_pd_start              = each.value.ipv6_pd_start
  ipv6_pd_stop               = each.value.ipv6_pd_stop
  ipv6_ra_enable             = each.value.ipv6_ra_enable
  ipv6_ra_preferred_lifetime = each.value.ipv6_ra_preferred_lifetime
  ipv6_ra_valid_lifetime     = each.value.ipv6_ra_valid_lifetime

  # Network Group
  network_group = each.value.network_group

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Local values for network organization
locals {
  # Organize networks by purpose for easier management
  wan_networks = {
    for k, v in var.networks : k => v
    if v.purpose == "wan"
  }

  lan_networks = {
    for k, v in var.networks : k => v
    if v.purpose == "lan"
  }

  vlan_networks = {
    for k, v in var.networks : k => v
    if v.purpose == "vlan-only"
  }

  # Networks with IPv6 enabled
  ipv6_networks = {
    for k, v in var.networks : k => v
    if v.ipv6_interface_type != null
  }

  # Networks with DHCP enabled
  dhcp_networks = {
    for k, v in var.networks : k => v
    if v.dhcp_enabled == true
  }
}