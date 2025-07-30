# UniFi BGP Configuration Module - Placeholder Implementation
#
# IMPORTANT: This module is currently a documentation placeholder.
# BGP configuration is NOT supported by the UniFi Terraform provider.
# Manual configuration is required through UniFi Network Application or SSH.

# Placeholder locals for BGP configuration structure
# These represent the intended configuration when provider support becomes available
locals {
  # BGP configuration structure for documentation purposes
  bgp_config = {
    enabled = var.bgp_enabled

    # Basic BGP parameters
    as_number = var.bgp_as_number
    router_id = var.bgp_router_id

    # BGP neighbors configuration
    neighbors = var.bgp_neighbors

    # Network advertisements
    advertised_networks = var.bgp_advertised_networks

    # Route filtering and policies
    route_maps   = var.bgp_route_maps
    prefix_lists = var.bgp_prefix_lists

    # IPv6 BGP configuration
    ipv6_enabled   = var.bgp_ipv6_enabled
    ipv6_neighbors = var.bgp_ipv6_neighbors
    ipv6_networks  = var.bgp_ipv6_networks
  }

  # Generate configuration summary for documentation
  bgp_summary = var.bgp_enabled ? {
    as_number      = var.bgp_as_number
    router_id      = var.bgp_router_id
    neighbor_count = length(var.bgp_neighbors)
    ipv4_networks  = length(var.bgp_advertised_networks)
    ipv6_enabled   = var.bgp_ipv6_enabled
    ipv6_networks  = var.bgp_ipv6_enabled ? length(var.bgp_ipv6_networks) : 0
  } : null
}

# Placeholder resource - This would be the actual BGP configuration
# when provider support becomes available
#
# resource "unifi_bgp" "main" {
#   count = var.bgp_enabled ? 1 : 0
#   
#   as_number = var.bgp_as_number
#   router_id = var.bgp_router_id
#   site      = var.site
#   
#   dynamic "neighbor" {
#     for_each = var.bgp_neighbors
#     content {
#       ip        = neighbor.value.ip
#       remote_as = neighbor.value.remote_as
#       description = neighbor.value.description
#       password    = neighbor.value.password
#       
#       # Authentication
#       auth_type = neighbor.value.auth_type
#       
#       # Timers
#       keepalive_timer = neighbor.value.keepalive_timer
#       hold_timer      = neighbor.value.hold_timer
#       
#       # Route filtering
#       route_map_in  = neighbor.value.route_map_in
#       route_map_out = neighbor.value.route_map_out
#       prefix_list_in  = neighbor.value.prefix_list_in
#       prefix_list_out = neighbor.value.prefix_list_out
#       
#       # Limits
#       maximum_prefix = neighbor.value.maximum_prefix
#     }
#   }
#   
#   # Network advertisements
#   dynamic "network" {
#     for_each = var.bgp_advertised_networks
#     content {
#       prefix = network.value.prefix
#       route_map = network.value.route_map
#     }
#   }
#   
#   # IPv6 address family
#   dynamic "address_family_ipv6" {
#     for_each = var.bgp_ipv6_enabled ? [1] : []
#     content {
#       dynamic "neighbor" {
#         for_each = var.bgp_ipv6_neighbors
#         content {
#           ip        = neighbor.value.ip
#           remote_as = neighbor.value.remote_as
#           activate  = neighbor.value.activate
#         }
#       }
#       
#       dynamic "network" {
#         for_each = var.bgp_ipv6_networks
#         content {
#           prefix = network.value.prefix
#         }
#       }
#     }
#   }
# }

# Placeholder for route maps configuration
# resource "unifi_route_map" "bgp_route_maps" {
#   for_each = var.bgp_route_maps
#   
#   name = each.key
#   site = var.site
#   
#   dynamic "rule" {
#     for_each = each.value.rules
#     content {
#       sequence = rule.value.sequence
#       action   = rule.value.action
#       
#       # Match conditions
#       match_prefix_list = rule.value.match_prefix_list
#       match_as_path     = rule.value.match_as_path
#       match_community   = rule.value.match_community
#       
#       # Set actions
#       set_local_preference = rule.value.set_local_preference
#       set_metric          = rule.value.set_metric
#       set_community       = rule.value.set_community
#     }
#   }
# }

# Placeholder for prefix lists configuration
# resource "unifi_prefix_list" "bgp_prefix_lists" {
#   for_each = var.bgp_prefix_lists
#   
#   name = each.key
#   site = var.site
#   
#   dynamic "rule" {
#     for_each = each.value.rules
#     content {
#       sequence = rule.value.sequence
#       action   = rule.value.action
#       prefix   = rule.value.prefix
#       ge       = rule.value.ge
#       le       = rule.value.le
#     }
#   }
# }

# Data source to validate network configuration compatibility
data "unifi_network" "bgp_networks" {
  for_each = var.bgp_enabled ? toset([
    for net in var.bgp_advertised_networks : net.prefix
    if can(regex("^192\\.168\\.|^10\\.|^172\\.(1[6-9]|2[0-9]|3[01])\\.", net.prefix))
  ]) : toset([])

  # This would validate that advertised networks exist in UniFi configuration
  # Currently just a placeholder for future implementation
}

# Generate manual configuration script
resource "local_file" "bgp_manual_config" {
  count = var.bgp_enabled && var.generate_manual_config ? 1 : 0

  filename = "${path.module}/generated/bgp_manual_config.sh"
  content = templatefile("${path.module}/templates/bgp_config.sh.tpl", {
    bgp_config = local.bgp_config
    site       = var.site
  })

  file_permission = "0755"
}

# Generate JSON configuration for manual import
resource "local_file" "bgp_json_config" {
  count = var.bgp_enabled && var.generate_json_config ? 1 : 0

  filename = "${path.module}/generated/bgp_config.json"
  content = jsonencode({
    bgp = local.bgp_config
    metadata = {
      generated_at           = timestamp()
      terraform_version      = ">=1.5.0"
      provider_version       = "~>0.41.0"
      manual_config_required = true
    }
  })
}

# Create documentation file with current configuration
resource "local_file" "bgp_documentation" {
  count = var.bgp_enabled ? 1 : 0

  filename = "${path.module}/generated/BGP_Configuration_Guide.md"
  content = templatefile("${path.module}/templates/bgp_documentation.md.tpl", {
    bgp_config  = local.bgp_config
    bgp_summary = local.bgp_summary
    site        = var.site
  })
}