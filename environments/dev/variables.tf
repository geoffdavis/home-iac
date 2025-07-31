# Variables for the dev environment

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

# TEMPORARILY DISABLED - UniFi Controller Variables
# variable "unifi_username" {
#   description = "UniFi Controller username"
#   type        = string
#   sensitive   = true
# }

# variable "unifi_password" {
#   description = "UniFi Controller password/API key"
#   type        = string
#   sensitive   = true
# }

# variable "unifi_api_url" {
#   description = "UniFi Controller API URL"
#   type        = string
#   default     = "https://unifi.home.geoffdavis.com"
# }

# variable "unifi_allow_insecure" {
#   description = "Allow insecure TLS connections (for development)"
#   type        = bool
#   default     = false
# }

# variable "unifi_site" {
#   description = "UniFi site name"
#   type        = string
#   default     = "default"
# }

# TEMPORARILY DISABLED - WiFi/WLAN Configuration Variables
# variable "main_wifi_passphrase" {
#   description = "Passphrase for the main WiFi network"
#   type        = string
#   sensitive   = true
# }

# variable "guest_wifi_passphrase" {
#   description = "Passphrase for the guest WiFi network"
#   type        = string
#   sensitive   = true
# }

# variable "iot_wifi_passphrase" {
#   description = "Passphrase for the IoT WiFi network"
#   type        = string
#   sensitive   = true
# }

# variable "management_wifi_passphrase" {
#   description = "Passphrase for the management WiFi network"
#   type        = string
#   sensitive   = true
# }

# variable "performance_wifi_passphrase" {
#   description = "Passphrase for the high-performance WiFi network"
#   type        = string
#   sensitive   = true
# }

# variable "legacy_wifi_passphrase" {
#   description = "Passphrase for the legacy 2.4GHz WiFi network"
#   type        = string
#   sensitive   = true
# }

# TEMPORARILY DISABLED - Management WiFi Access Control
# variable "enable_management_mac_filtering" {
#   description = "Enable MAC address filtering for management WiFi"
#   type        = bool
#   default     = false
# }

# variable "management_allowed_macs" {
#   description = "List of MAC addresses allowed on management WiFi"
#   type        = list(string)
#   default     = []
# }

# variable "management_wifi_schedule" {
#   description = "Schedule for management WiFi availability (e.g., ['mon|8:00-17:00', 'tue|8:00-17:00'])"
#   type        = list(string)
#   default     = []
# }

# TEMPORARILY DISABLED - BGP Configuration Variables
# IMPORTANT: BGP configuration is NOT supported by the UniFi Terraform provider.
# These variables are for documentation and planning purposes only.

# variable "bgp_enabled" {
#   description = "Enable BGP configuration documentation (manual configuration required)"
#   type        = bool
#   default     = false
# }

# variable "bgp_as_number" {
#   description = "BGP Autonomous System (AS) number"
#   type        = number
#   default     = 65001
#
#   validation {
#     condition     = var.bgp_as_number >= 1 && var.bgp_as_number <= 4294967295
#     error_message = "BGP AS number must be between 1 and 4294967295."
#   }
# }

# variable "bgp_router_id" {
#   description = "BGP Router ID (typically an IPv4 address)"
#   type        = string
#   default     = "192.168.1.1"
#
#   validation {
#     condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.bgp_router_id))
#     error_message = "BGP Router ID must be a valid IPv4 address."
#   }
# }

# variable "bgp_neighbors" {
#   description = "BGP neighbor configurations"
#   type = list(object({
#     ip                = string
#     remote_as         = number
#     description       = optional(string, "")
#     password          = optional(string)
#     auth_type         = optional(string, "md5")
#     keepalive_timer   = optional(number, 60)
#     hold_timer        = optional(number, 180)
#     route_map_in      = optional(string)
#     route_map_out     = optional(string)
#     prefix_list_in    = optional(string)
#     prefix_list_out   = optional(string)
#     maximum_prefix    = optional(number, 1000)
#     next_hop_self     = optional(bool, false)
#     remove_private_as = optional(bool, false)
#   }))
#   default = []
# }

# variable "bgp_advertised_networks" {
#   description = "Networks to advertise via BGP"
#   type = list(object({
#     prefix    = string
#     route_map = optional(string)
#     metric    = optional(number)
#   }))
#   default = []
# }

# variable "bgp_route_maps" {
#   description = "BGP route map configurations"
#   type = map(object({
#     rules = list(object({
#       sequence             = number
#       action               = string # permit or deny
#       match_prefix_list    = optional(string)
#       match_as_path        = optional(string)
#       match_community      = optional(string)
#       set_local_preference = optional(number)
#       set_metric           = optional(number)
#       set_community        = optional(string)
#       set_as_path_prepend  = optional(string)
#     }))
#   }))
#   default = {}
# }

# variable "bgp_prefix_lists" {
#   description = "BGP prefix list configurations"
#   type = map(object({
#     rules = list(object({
#       sequence = number
#       action   = string # permit or deny
#       prefix   = string
#       ge       = optional(number)
#       le       = optional(number)
#     }))
#   }))
#   default = {}
# }

# variable "bgp_ipv6_enabled" {
#   description = "Enable IPv6 BGP configuration"
#   type        = bool
#   default     = false
# }

# variable "bgp_ipv6_neighbors" {
#   description = "IPv6 BGP neighbor configurations"
#   type = list(object({
#     ip          = string
#     remote_as   = number
#     activate    = optional(bool, true)
#     description = optional(string, "")
#   }))
#   default = []
# }

# variable "bgp_ipv6_networks" {
#   description = "IPv6 networks to advertise via BGP"
#   type = list(object({
#     prefix = string
#   }))
#   default = []
# }

# Advanced BGP Configuration Variables

# variable "bgp_confederation" {
#   description = "BGP confederation configuration"
#   type = object({
#     enabled    = bool
#     identifier = optional(number)
#     peers      = optional(list(number), [])
#   })
#   default = {
#     enabled = false
#   }
# }

# variable "bgp_route_reflector" {
#   description = "BGP route reflector configuration"
#   type = object({
#     enabled    = bool
#     cluster_id = optional(string)
#     clients    = optional(list(string), [])
#   })
#   default = {
#     enabled = false
#   }
# }

# variable "bgp_graceful_restart" {
#   description = "BGP graceful restart configuration"
#   type = object({
#     enabled         = bool
#     restart_time    = optional(number, 120)
#     stale_path_time = optional(number, 360)
#   })
#   default = {
#     enabled = false
#   }
# }

# variable "bgp_multipath" {
#   description = "BGP multipath configuration"
#   type = object({
#     enabled = bool
#     maximum = optional(number, 1)
#     ibgp    = optional(bool, false)
#     ebgp    = optional(bool, false)
#   })
#   default = {
#     enabled = false
#   }
# }

# variable "bgp_dampening" {
#   description = "BGP route dampening configuration"
#   type = object({
#     enabled            = bool
#     half_life          = optional(number, 15)
#     reuse_threshold    = optional(number, 750)
#     suppress_threshold = optional(number, 2000)
#     max_suppress_time  = optional(number, 60)
#   })
#   default = {
#     enabled = false
#   }
# }

# variable "bgp_communities" {
#   description = "BGP community configurations"
#   type = map(object({
#     value       = string
#     description = optional(string, "")
#   }))
#   default = {}
# }

# variable "bgp_as_path_lists" {
#   description = "BGP AS path list configurations"
#   type = map(object({
#     rules = list(object({
#       sequence = number
#       action   = string # permit or deny
#       regex    = string
#     }))
#   }))
#   default = {}
# }

# File Generation Options

# variable "generate_bgp_manual_config" {
#   description = "Generate manual BGP configuration script"
#   type        = bool
#   default     = true
# }

# variable "generate_bgp_json_config" {
#   description = "Generate JSON BGP configuration file"
#   type        = bool
#   default     = true
# }