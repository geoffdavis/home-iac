# Variables for UniFi WLANs Module

variable "wlans" {
  description = "Map of UniFi WLAN configurations"
  type = map(object({
    name                 = string
    network_id           = string
    passphrase           = optional(string)
    security             = optional(string, "wpapsk")
    wpa3_support         = optional(bool, true)
    wpa3_transition      = optional(bool, true)
    pmf_mode             = optional(string, "optional")
    is_guest             = optional(bool, false)
    user_group_id        = optional(string)
    hide_ssid            = optional(bool, false)
    mac_filter_enabled   = optional(bool, false)
    mac_filter_policy    = optional(string, "allow")
    mac_filter_list      = optional(list(string), [])
    radius_profile_id    = optional(string)
    schedule             = optional(list(string), [])
    uapsd                = optional(bool, true)
    dtim_mode            = optional(string, "default")
    dtim_na              = optional(number, 1)
    dtim_ng              = optional(number, 1)
    multicast_enhance    = optional(bool, false)
    no2ghz_oui           = optional(bool, false)
    proxy_arp            = optional(bool, false)
    l2_isolation         = optional(bool, false)
    bss_transition       = optional(bool, true)
    fast_roaming_enabled = optional(bool, true)
    hotspot2_conf        = optional(bool, false)
    wlan_band            = optional(string, "both")
    ap_group_ids         = optional(list(string), [])
    ap_group_mode        = optional(string, "all")
    minimum_data_rate_2g = optional(number, 1000)
    minimum_data_rate_5g = optional(number, 6000)
    minimum_data_rate_6g = optional(number, 6000)
    multicast_rate       = optional(number, 6000)
    bc_filter_enabled    = optional(bool, false)
    bc_filter_list       = optional(list(string), [])
    site                 = optional(string)
  }))
  default = {}
}

variable "site" {
  description = "UniFi site name (default site if not specified per WLAN)"
  type        = string
  default     = "default"
}

variable "common_tags" {
  description = "Common tags to apply to all resources (for documentation purposes)"
  type        = map(string)
  default     = {}
}

variable "default_security" {
  description = "Default security mode for WLANs"
  type        = string
  default     = "wpapsk"
  validation {
    condition = contains([
      "open", "wpapsk", "wpaeap", "wpa3sae", "wpa3eap192", "wpa3eap"
    ], var.default_security)
    error_message = "Security mode must be one of: open, wpapsk, wpaeap, wpa3sae, wpa3eap192, wpa3eap."
  }
}

variable "default_wpa3_support" {
  description = "Default WPA3 support setting"
  type        = bool
  default     = true
}

variable "default_wpa3_transition" {
  description = "Default WPA3 transition mode setting"
  type        = bool
  default     = true
}

variable "default_pmf_mode" {
  description = "Default Protected Management Frames mode"
  type        = string
  default     = "optional"
  validation {
    condition     = contains(["disabled", "optional", "required"], var.default_pmf_mode)
    error_message = "PMF mode must be one of: disabled, optional, required."
  }
}

variable "default_wlan_band" {
  description = "Default WLAN band setting"
  type        = string
  default     = "both"
  validation {
    condition     = contains(["2g", "5g", "6g", "both"], var.default_wlan_band)
    error_message = "WLAN band must be one of: 2g, 5g, 6g, both."
  }
}

variable "default_minimum_data_rate_2g" {
  description = "Default minimum data rate for 2.4GHz band (kbps)"
  type        = number
  default     = 1000
}

variable "default_minimum_data_rate_5g" {
  description = "Default minimum data rate for 5GHz band (kbps)"
  type        = number
  default     = 6000
}

variable "default_minimum_data_rate_6g" {
  description = "Default minimum data rate for 6GHz band (kbps)"
  type        = number
  default     = 6000
}

variable "default_multicast_rate" {
  description = "Default multicast rate (kbps)"
  type        = number
  default     = 6000
}

variable "enable_fast_roaming" {
  description = "Enable fast roaming (802.11r) by default"
  type        = bool
  default     = true
}

variable "enable_bss_transition" {
  description = "Enable BSS transition (802.11v) by default"
  type        = bool
  default     = true
}

variable "enable_uapsd" {
  description = "Enable Unscheduled Automatic Power Save Delivery by default"
  type        = bool
  default     = true
}

variable "guest_network_isolation" {
  description = "Enable L2 isolation for guest networks by default"
  type        = bool
  default     = true
}

variable "guest_proxy_arp" {
  description = "Enable proxy ARP for guest networks by default"
  type        = bool
  default     = true
}