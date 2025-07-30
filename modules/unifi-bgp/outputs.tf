# Outputs for UniFi BGP Module
#
# IMPORTANT: This module is currently a documentation placeholder.
# BGP configuration is NOT supported by the UniFi Terraform provider.

output "bgp_configuration_summary" {
  description = "Summary of BGP configuration (for documentation purposes)"
  value = var.bgp_enabled ? {
    enabled             = var.bgp_enabled
    as_number           = var.bgp_as_number
    router_id           = var.bgp_router_id
    neighbor_count      = length(var.bgp_neighbors)
    ipv4_networks       = length(var.bgp_advertised_networks)
    ipv6_enabled        = var.bgp_ipv6_enabled
    ipv6_neighbor_count = length(var.bgp_ipv6_neighbors)
    ipv6_networks       = length(var.bgp_ipv6_networks)
    route_maps          = keys(var.bgp_route_maps)
    prefix_lists        = keys(var.bgp_prefix_lists)
    site                = var.site
  } : null
}

output "bgp_neighbors" {
  description = "BGP neighbor configurations"
  value = var.bgp_enabled ? {
    ipv4 = [
      for neighbor in var.bgp_neighbors : {
        ip          = neighbor.ip
        remote_as   = neighbor.remote_as
        description = neighbor.description
        # Sensitive fields excluded from output
      }
    ]
    ipv6 = var.bgp_ipv6_enabled ? [
      for neighbor in var.bgp_ipv6_neighbors : {
        ip          = neighbor.ip
        remote_as   = neighbor.remote_as
        description = neighbor.description
      }
    ] : []
  } : null
}

output "bgp_advertised_networks" {
  description = "Networks advertised via BGP"
  value = var.bgp_enabled ? {
    ipv4 = [
      for network in var.bgp_advertised_networks : {
        prefix    = network.prefix
        route_map = network.route_map
        metric    = network.metric
      }
    ]
    ipv6 = var.bgp_ipv6_enabled ? [
      for network in var.bgp_ipv6_networks : {
        prefix = network.prefix
      }
    ] : []
  } : null
}

output "bgp_route_policies" {
  description = "BGP routing policies configuration"
  value = var.bgp_enabled ? {
    route_maps = {
      for name, config in var.bgp_route_maps : name => {
        rule_count = length(config.rules)
        rules = [
          for rule in config.rules : {
            sequence = rule.sequence
            action   = rule.action
            # Match conditions
            match_prefix_list = rule.match_prefix_list
            match_as_path     = rule.match_as_path
            match_community   = rule.match_community
            # Set actions
            set_local_preference = rule.set_local_preference
            set_metric           = rule.set_metric
            set_community        = rule.set_community
          }
        ]
      }
    }
    prefix_lists = {
      for name, config in var.bgp_prefix_lists : name => {
        rule_count = length(config.rules)
        rules = [
          for rule in config.rules : {
            sequence = rule.sequence
            action   = rule.action
            prefix   = rule.prefix
            ge       = rule.ge
            le       = rule.le
          }
        ]
      }
    }
  } : null
}

output "bgp_advanced_features" {
  description = "BGP advanced feature configurations"
  value = var.bgp_enabled ? {
    confederation = var.bgp_confederation.enabled ? {
      identifier = var.bgp_confederation.identifier
      peers      = var.bgp_confederation.peers
    } : null

    route_reflector = var.bgp_route_reflector.enabled ? {
      cluster_id = var.bgp_route_reflector.cluster_id
      clients    = var.bgp_route_reflector.clients
    } : null

    graceful_restart = var.bgp_graceful_restart.enabled ? {
      restart_time    = var.bgp_graceful_restart.restart_time
      stale_path_time = var.bgp_graceful_restart.stale_path_time
    } : null

    multipath = var.bgp_multipath.enabled ? {
      maximum = var.bgp_multipath.maximum
      ibgp    = var.bgp_multipath.ibgp
      ebgp    = var.bgp_multipath.ebgp
    } : null

    dampening = var.bgp_dampening.enabled ? {
      half_life          = var.bgp_dampening.half_life
      reuse_threshold    = var.bgp_dampening.reuse_threshold
      suppress_threshold = var.bgp_dampening.suppress_threshold
      max_suppress_time  = var.bgp_dampening.max_suppress_time
    } : null
  } : null
}

output "manual_configuration_required" {
  description = "Indicates that manual configuration is required"
  value = var.bgp_enabled ? {
    provider_limitation  = "BGP configuration is not supported by the UniFi Terraform provider"
    manual_config_needed = true
    configuration_methods = [
      "UniFi Network Application (if BGP features are available)",
      "SSH access to UDM Pro",
      "Direct API calls to UniFi Controller",
      "Configuration management tools (Ansible, etc.)"
    ]
    generated_files = {
      manual_script = var.generate_manual_config ? "${path.module}/generated/bgp_manual_config.sh" : null
      json_config   = var.generate_json_config ? "${path.module}/generated/bgp_config.json" : null
      documentation = "${path.module}/generated/BGP_Configuration_Guide.md"
    }
  } : null
}

output "bgp_validation_warnings" {
  description = "Validation warnings and recommendations"
  value = var.bgp_enabled ? {
    warnings = concat(
      # Check for private AS numbers
      [
        for neighbor in var.bgp_neighbors :
        "Neighbor ${neighbor.ip} uses AS ${neighbor.remote_as} - verify AS number assignment"
        if neighbor.remote_as >= 64512 && neighbor.remote_as <= 65534
      ],
      # Check for RFC 6996 private AS numbers
      [
        for neighbor in var.bgp_neighbors :
        "Neighbor ${neighbor.ip} uses private AS ${neighbor.remote_as} (RFC 6996)"
        if neighbor.remote_as >= 4200000000 && neighbor.remote_as <= 4294967294
      ],
      # Check for network overlap with existing UniFi networks
      [
        for network in var.bgp_advertised_networks :
        "Network ${network.prefix} may overlap with UniFi managed networks - verify configuration"
        if can(regex("^192\\.168\\.|^10\\.|^172\\.(1[6-9]|2[0-9]|3[01])\\.", network.prefix))
      ]
    )

    recommendations = [
      "Verify BGP AS number assignments with network administrator",
      "Ensure advertised networks don't conflict with existing UniFi VLANs",
      "Configure BGP authentication for all external neighbors",
      "Implement route filtering to prevent route leaks",
      "Test BGP configuration in development environment first",
      "Document all BGP neighbors and their purposes",
      "Monitor BGP neighbor states and route advertisements"
    ]
  } : null
}

output "terraform_integration_status" {
  description = "Status of Terraform integration for BGP"
  value = {
    provider_version = "~> 0.41.0"
    bgp_support      = "Not Available"
    last_checked     = "2025-01-24"
    alternative_approaches = [
      "Manual configuration through UniFi Network Application",
      "SSH-based configuration scripts",
      "Configuration management tools (Ansible, Puppet, Chef)",
      "Custom API integration scripts"
    ]
    future_enhancement_path = [
      "Monitor UniFi provider releases for BGP support",
      "Consider contributing BGP resources to provider",
      "Evaluate alternative UniFi management tools",
      "Plan migration strategy when BGP support becomes available"
    ]
  }
}

# Local file outputs (when files are generated)
output "generated_files" {
  description = "Paths to generated configuration files"
  value = var.bgp_enabled ? {
    manual_config_script = var.generate_manual_config ? abspath("${path.module}/generated/bgp_manual_config.sh") : null
    json_configuration   = var.generate_json_config ? abspath("${path.module}/generated/bgp_config.json") : null
    documentation_guide  = abspath("${path.module}/generated/BGP_Configuration_Guide.md")
  } : null
}