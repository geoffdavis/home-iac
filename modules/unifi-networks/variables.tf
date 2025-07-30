# Variables for UniFi Networks Module

variable "networks" {
  description = "Map of UniFi network configurations"
  type = map(object({
    name                       = string
    purpose                    = string # wan, lan, vlan-only
    vlan_id                    = optional(number)
    subnet                     = optional(string)
    dhcp_enabled               = optional(bool, true)
    dhcp_start                 = optional(string)
    dhcp_stop                  = optional(string)
    dhcp_dns                   = optional(list(string))
    dhcp_lease_time            = optional(number, 86400)
    domain_name                = optional(string)
    igmp_snooping              = optional(bool, false)
    multicast_dns              = optional(bool, false)
    wan_networkgroup           = optional(string)
    wan_type                   = optional(string, "dhcp")
    wan_ip                     = optional(string)
    wan_netmask                = optional(string)
    wan_gateway                = optional(string)
    wan_dns                    = optional(list(string))
    wan_username               = optional(string)
    wan_password               = optional(string)
    wan_egress_qos             = optional(number)
    wan_ingress_qos            = optional(number)
    ipv6_interface_type        = optional(string)
    ipv6_pd_interface          = optional(string)
    ipv6_pd_prefixid           = optional(string)
    ipv6_pd_start              = optional(string)
    ipv6_pd_stop               = optional(string)
    ipv6_ra_enable             = optional(bool, false)
    ipv6_ra_preferred_lifetime = optional(number)
    ipv6_ra_valid_lifetime     = optional(number)
    network_group              = optional(string)
    site                       = optional(string)
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all resources (for documentation purposes)"
  type        = map(string)
  default     = {}
}

variable "site" {
  description = "UniFi site name (default site if not specified per network)"
  type        = string
  default     = "default"
}

variable "default_domain_name" {
  description = "Default domain name for networks"
  type        = string
  default     = "home.local"
}

variable "default_dns_servers" {
  description = "Default DNS servers for DHCP"
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}