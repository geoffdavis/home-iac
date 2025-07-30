# UniFi BGP Configuration for Dev Environment
#
# IMPORTANT: This configuration is for documentation purposes only.
# BGP configuration is NOT supported by the UniFi Terraform provider.
# Manual configuration is required through UniFi Network Application or SSH.

# UniFi BGP Module (Documentation/Planning Only)
module "unifi_bgp" {
  source = "../../modules/unifi-bgp"

  # Enable BGP configuration documentation
  bgp_enabled = var.bgp_enabled

  # Basic BGP Configuration
  bgp_as_number = var.bgp_as_number
  bgp_router_id = var.bgp_router_id
  site          = var.unifi_site

  # BGP Neighbors Configuration
  bgp_neighbors = var.bgp_neighbors

  # Network Advertisements
  bgp_advertised_networks = var.bgp_advertised_networks

  # Route Policies
  bgp_route_maps   = var.bgp_route_maps
  bgp_prefix_lists = var.bgp_prefix_lists

  # IPv6 BGP Configuration
  bgp_ipv6_enabled   = var.bgp_ipv6_enabled
  bgp_ipv6_neighbors = var.bgp_ipv6_neighbors
  bgp_ipv6_networks  = var.bgp_ipv6_networks

  # Advanced BGP Features
  bgp_confederation    = var.bgp_confederation
  bgp_route_reflector  = var.bgp_route_reflector
  bgp_graceful_restart = var.bgp_graceful_restart
  bgp_multipath        = var.bgp_multipath
  bgp_dampening        = var.bgp_dampening

  # BGP Communities and AS Path Lists
  bgp_communities   = var.bgp_communities
  bgp_as_path_lists = var.bgp_as_path_lists

  # File Generation Options
  generate_manual_config = var.generate_bgp_manual_config
  generate_json_config   = var.generate_bgp_json_config

  # Common tags for documentation
  common_tags = local.common_tags
}

# Example BGP Configuration Values
# These would typically be defined in terraform.tfvars or through variables
#
# Example configuration structure for reference:
#
# bgp_neighbors = [
#   {
#     ip          = "203.0.113.1"
#     remote_as   = 65000
#     description = "ISP Primary Connection"
#     password    = "secure_bgp_password_123"
#     auth_type   = "md5"
#   },
#   {
#     ip          = "198.51.100.1"
#     remote_as   = 65002
#     description = "Peer Network Connection"
#   }
# ]
#
# bgp_advertised_networks = [
#   {
#     prefix = "192.168.0.0/16"
#     route_map = "LOCAL_NETWORKS"
#   }
# ]

# Outputs for BGP configuration
output "bgp_configuration_summary" {
  description = "Summary of BGP configuration (documentation only)"
  value       = module.unifi_bgp.bgp_configuration_summary
}

output "bgp_manual_configuration_required" {
  description = "Manual configuration requirements and methods"
  value       = module.unifi_bgp.manual_configuration_required
}

output "bgp_neighbors_summary" {
  description = "BGP neighbors configuration summary"
  value       = module.unifi_bgp.bgp_neighbors
}

output "bgp_advertised_networks" {
  description = "Networks advertised via BGP"
  value       = module.unifi_bgp.bgp_advertised_networks
}

output "bgp_route_policies" {
  description = "BGP routing policies (route maps and prefix lists)"
  value       = module.unifi_bgp.bgp_route_policies
}

output "bgp_validation_warnings" {
  description = "BGP configuration validation warnings"
  value       = module.unifi_bgp.bgp_validation_warnings
}

output "bgp_generated_files" {
  description = "Paths to generated BGP configuration files"
  value       = module.unifi_bgp.generated_files
}

output "terraform_bgp_integration_status" {
  description = "Status of Terraform BGP integration"
  value       = module.unifi_bgp.terraform_integration_status
}

# Integration with existing network configuration
# This shows how BGP would integrate with the existing UniFi networks

locals {
  # Validate that BGP advertised networks align with UniFi network configuration
  bgp_network_validation = var.bgp_enabled ? {
    # Check if advertised networks match configured UniFi networks
    unifi_networks = keys(module.unifi_networks.network_ids)
    bgp_networks   = [for net in var.bgp_advertised_networks : net.prefix]

    # Potential conflicts or overlaps
    validation_notes = [
      "Ensure BGP advertised networks don't conflict with UniFi VLAN subnets",
      "Verify firewall rules allow BGP traffic (TCP port 179)",
      "Consider impact on existing DHCP configurations",
      "Review DNS implications of route advertisements"
    ]
  } : null
}

output "bgp_unifi_integration_notes" {
  description = "Notes on BGP integration with existing UniFi configuration"
  value       = local.bgp_network_validation
}

# Example of how BGP configuration would be documented alongside network config
output "network_and_bgp_summary" {
  description = "Combined summary of UniFi networks and BGP configuration"
  value = {
    unifi_networks = {
      total_networks = length(keys(module.unifi_networks.network_ids))
      vlan_networks  = length(keys(module.unifi_networks.vlan_networks))
      wan_networks   = length(keys(module.unifi_networks.wan_networks))
      ipv6_enabled   = length([for net in module.unifi_networks.network_summary : net if net.ipv6_enabled]) > 0
    }
    bgp_configuration = var.bgp_enabled ? {
      status              = "Manual Configuration Required"
      as_number           = var.bgp_as_number
      neighbors           = length(var.bgp_neighbors)
      advertised_networks = length(var.bgp_advertised_networks)
      provider_support    = "Not Available"
      } : {
      status           = "Disabled"
      provider_support = "Not Available"
    }
    integration_status = {
      terraform_managed = "UniFi Networks, WLANs, Firewall Rules"
      manual_required   = "BGP Configuration"
      hybrid_approach   = "Terraform + Manual Configuration"
    }
  }
}