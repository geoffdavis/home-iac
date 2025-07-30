# UniFi Networks Configuration for Dev Environment

# UniFi Networks Module
module "unifi_networks" {
  source = "../../modules/unifi-networks"

  site                = var.unifi_site
  default_domain_name = "home.local"
  default_dns_servers = ["1.1.1.1", "1.0.0.1", "8.8.8.8"]
  common_tags         = local.common_tags

  networks = {
    # WAN Configuration with IPv6 Prefix Delegation
    wan = {
      name                = "WAN"
      purpose             = "wan"
      wan_type            = "dhcp"
      wan_egress_qos      = 0
      wan_ingress_qos     = 0
      ipv6_interface_type = "pd"
      ipv6_pd_interface   = "wan"
      ipv6_pd_prefixid    = "0"
    }

    # Main LAN Network
    main_lan = {
      name         = "Main LAN"
      purpose      = "lan"
      vlan_id      = 1
      subnet       = "192.168.1.0/24"
      dhcp_enabled = true
      dhcp_start   = "192.168.1.100"
      dhcp_stop    = "192.168.1.200"
      dhcp_dns     = ["192.168.1.1", "1.1.1.1", "1.0.0.1"]
      domain_name  = "home.local"

      # IPv6 Configuration
      ipv6_interface_type        = "pd"
      ipv6_pd_interface          = "wan"
      ipv6_pd_prefixid           = "1"
      ipv6_pd_start              = "::2"
      ipv6_pd_stop               = "::7fff:ffff:ffff:fffe"
      ipv6_ra_enable             = true
      ipv6_ra_preferred_lifetime = 14400
      ipv6_ra_valid_lifetime     = 86400

      igmp_snooping = true
      multicast_dns = true
    }

    # Guest Network VLAN
    guest = {
      name         = "Guest Network"
      purpose      = "vlan-only"
      vlan_id      = 10
      subnet       = "192.168.10.0/24"
      dhcp_enabled = true
      dhcp_start   = "192.168.10.100"
      dhcp_stop    = "192.168.10.200"
      dhcp_dns     = ["1.1.1.1", "1.0.0.1"]
      domain_name  = "guest.local"

      # IPv6 Configuration
      ipv6_interface_type        = "pd"
      ipv6_pd_interface          = "wan"
      ipv6_pd_prefixid           = "10"
      ipv6_pd_start              = "::2"
      ipv6_pd_stop               = "::7fff:ffff:ffff:fffe"
      ipv6_ra_enable             = true
      ipv6_ra_preferred_lifetime = 14400
      ipv6_ra_valid_lifetime     = 86400

      igmp_snooping = false
      multicast_dns = false
    }

    # IoT Devices VLAN
    iot = {
      name         = "IoT Devices"
      purpose      = "vlan-only"
      vlan_id      = 20
      subnet       = "192.168.20.0/24"
      dhcp_enabled = true
      dhcp_start   = "192.168.20.100"
      dhcp_stop    = "192.168.20.200"
      dhcp_dns     = ["192.168.1.1", "1.1.1.1"]
      domain_name  = "iot.local"

      # IPv6 Configuration
      ipv6_interface_type        = "pd"
      ipv6_pd_interface          = "wan"
      ipv6_pd_prefixid           = "20"
      ipv6_pd_start              = "::2"
      ipv6_pd_stop               = "::7fff:ffff:ffff:fffe"
      ipv6_ra_enable             = true
      ipv6_ra_preferred_lifetime = 14400
      ipv6_ra_valid_lifetime     = 86400

      igmp_snooping = true
      multicast_dns = true
    }

    # Management VLAN
    management = {
      name         = "Management"
      purpose      = "vlan-only"
      vlan_id      = 30
      subnet       = "192.168.30.0/24"
      dhcp_enabled = true
      dhcp_start   = "192.168.30.100"
      dhcp_stop    = "192.168.30.150"
      dhcp_dns     = ["192.168.1.1", "1.1.1.1", "1.0.0.1"]
      domain_name  = "mgmt.local"

      # IPv6 Configuration
      ipv6_interface_type        = "pd"
      ipv6_pd_interface          = "wan"
      ipv6_pd_prefixid           = "30"
      ipv6_pd_start              = "::2"
      ipv6_pd_stop               = "::7fff:ffff:ffff:fffe"
      ipv6_ra_enable             = true
      ipv6_ra_preferred_lifetime = 14400
      ipv6_ra_valid_lifetime     = 86400

      igmp_snooping = false
      multicast_dns = false
    }

    # Security Cameras VLAN
    cameras = {
      name         = "Security Cameras"
      purpose      = "vlan-only"
      vlan_id      = 40
      subnet       = "192.168.40.0/24"
      dhcp_enabled = true
      dhcp_start   = "192.168.40.100"
      dhcp_stop    = "192.168.40.200"
      dhcp_dns     = ["192.168.1.1"]
      domain_name  = "cameras.local"

      # IPv6 Configuration
      ipv6_interface_type        = "pd"
      ipv6_pd_interface          = "wan"
      ipv6_pd_prefixid           = "40"
      ipv6_pd_start              = "::2"
      ipv6_pd_stop               = "::7fff:ffff:ffff:fffe"
      ipv6_ra_enable             = true
      ipv6_ra_preferred_lifetime = 14400
      ipv6_ra_valid_lifetime     = 86400

      igmp_snooping = false
      multicast_dns = false
    }
  }
}

# Outputs for network information
output "unifi_network_summary" {
  description = "Summary of UniFi networks created"
  value       = module.unifi_networks.network_summary
}

output "unifi_network_ids" {
  description = "Map of network names to IDs"
  value       = module.unifi_networks.network_ids
}

output "unifi_lan_networks" {
  description = "LAN network configurations"
  value       = module.unifi_networks.lan_networks
}

output "unifi_vlan_networks" {
  description = "VLAN network configurations"
  value       = module.unifi_networks.vlan_networks
}

output "unifi_wan_networks" {
  description = "WAN network configurations"
  value       = module.unifi_networks.wan_networks
}