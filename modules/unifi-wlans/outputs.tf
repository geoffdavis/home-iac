# Outputs for UniFi WLANs Module

output "wlan_ids" {
  description = "Map of WLAN names to WLAN IDs"
  value       = { for k, v in unifi_wlan.this : k => v.id }
}

output "wlan_names" {
  description = "Map of WLAN keys to WLAN names"
  value       = { for k, v in unifi_wlan.this : k => v.name }
}

output "wlan_network_ids" {
  description = "Map of WLAN keys to network IDs"
  value       = { for k, v in unifi_wlan.this : k => v.network_id }
}

output "wlan_security_modes" {
  description = "Map of WLAN keys to security modes"
  value       = { for k, v in unifi_wlan.this : k => v.security }
}

output "wlan_bands" {
  description = "Map of WLAN keys to band configurations"
  value       = { for k, v in unifi_wlan.this : k => v.wlan_band }
}

output "guest_wlans" {
  description = "Map of guest WLAN configurations"
  value = {
    for k, v in unifi_wlan.this : k => {
      id            = v.id
      name          = v.name
      network_id    = v.network_id
      security      = v.security
      is_guest      = v.is_guest
      user_group_id = v.user_group_id
      l2_isolation  = v.l2_isolation
      proxy_arp     = v.proxy_arp
      wlan_band     = v.wlan_band
    } if v.is_guest == true
  }
}

output "secure_wlans" {
  description = "Map of secure (non-guest) WLAN configurations"
  value = {
    for k, v in unifi_wlan.this : k => {
      id                   = v.id
      name                 = v.name
      network_id           = v.network_id
      security             = v.security
      wpa3_support         = v.wpa3_support
      wpa3_transition      = v.wpa3_transition
      pmf_mode             = v.pmf_mode
      fast_roaming_enabled = v.fast_roaming_enabled
      bss_transition       = v.bss_transition
      wlan_band            = v.wlan_band
    } if v.is_guest != true
  }
}

output "enterprise_wlans" {
  description = "Map of enterprise authentication WLAN configurations"
  value = {
    for k, v in unifi_wlan.this : k => {
      id                = v.id
      name              = v.name
      network_id        = v.network_id
      security          = v.security
      radius_profile_id = v.radius_profile_id
      wlan_band         = v.wlan_band
    } if v.radius_profile_id != null
  }
}

output "mac_filtered_wlans" {
  description = "Map of MAC filtered WLAN configurations"
  value = {
    for k, v in unifi_wlan.this : k => {
      id                 = v.id
      name               = v.name
      network_id         = v.network_id
      mac_filter_enabled = v.mac_filter_enabled
      mac_filter_policy  = v.mac_filter_policy
      mac_filter_list    = v.mac_filter_list
      wlan_band          = v.wlan_band
    } if v.mac_filter_enabled == true
  }
}

output "scheduled_wlans" {
  description = "Map of scheduled WLAN configurations"
  value = {
    for k, v in unifi_wlan.this : k => {
      id         = v.id
      name       = v.name
      network_id = v.network_id
      schedule   = v.schedule
      wlan_band  = v.wlan_band
    } if length(v.schedule) > 0
  }
}

output "wlan_performance_settings" {
  description = "Map of WLAN performance and QoS settings"
  value = {
    for k, v in unifi_wlan.this : k => {
      id                   = v.id
      name                 = v.name
      uapsd                = v.uapsd
      dtim_mode            = v.dtim_mode
      dtim_na              = v.dtim_na
      dtim_ng              = v.dtim_ng
      multicast_enhance    = v.multicast_enhance
      minimum_data_rate_2g = v.minimum_data_rate_2g
      minimum_data_rate_5g = v.minimum_data_rate_5g
      minimum_data_rate_6g = v.minimum_data_rate_6g
      multicast_rate       = v.multicast_rate
      fast_roaming_enabled = v.fast_roaming_enabled
      bss_transition       = v.bss_transition
    }
  }
}

output "wlan_band_distribution" {
  description = "Distribution of WLANs by band configuration"
  value = {
    dual_band_count      = length(local.dual_band_wlans)
    single_band_2g_count = length(local.single_band_2g_wlans)
    single_band_5g_count = length(local.single_band_5g_wlans)
    single_band_6g_count = length(local.single_band_6g_wlans)
  }
}

output "wlan_security_distribution" {
  description = "Distribution of WLANs by security features"
  value = {
    wpa3_enabled_count    = length(local.wpa3_wlans)
    fast_roaming_count    = length(local.fast_roaming_wlans)
    bss_transition_count  = length(local.bss_transition_wlans)
    enterprise_auth_count = length(local.enterprise_wlans)
    mac_filtering_count   = length(local.mac_filtered_wlans)
  }
}

output "wlan_summary" {
  description = "Summary of all WLANs created"
  value = {
    total_wlans     = length(unifi_wlan.this)
    guest_count     = length(local.guest_wlans)
    secure_count    = length(local.secure_wlans)
    scheduled_count = length(local.scheduled_wlans)
  }
}

output "wlan_configurations" {
  description = "Complete WLAN configurations for reference"
  value = {
    for k, v in unifi_wlan.this : k => {
      id                   = v.id
      name                 = v.name
      network_id           = v.network_id
      security             = v.security
      wpa3_support         = v.wpa3_support
      wpa3_transition      = v.wpa3_transition
      pmf_mode             = v.pmf_mode
      is_guest             = v.is_guest
      user_group_id        = v.user_group_id
      hide_ssid            = v.hide_ssid
      mac_filter_enabled   = v.mac_filter_enabled
      mac_filter_policy    = v.mac_filter_policy
      radius_profile_id    = v.radius_profile_id
      schedule             = v.schedule
      uapsd                = v.uapsd
      dtim_mode            = v.dtim_mode
      multicast_enhance    = v.multicast_enhance
      proxy_arp            = v.proxy_arp
      l2_isolation         = v.l2_isolation
      bss_transition       = v.bss_transition
      fast_roaming_enabled = v.fast_roaming_enabled
      hotspot2_conf        = v.hotspot2_conf
      wlan_band            = v.wlan_band
      ap_group_ids         = v.ap_group_ids
      ap_group_mode        = v.ap_group_mode
      minimum_data_rate_2g = v.minimum_data_rate_2g
      minimum_data_rate_5g = v.minimum_data_rate_5g
      minimum_data_rate_6g = v.minimum_data_rate_6g
      multicast_rate       = v.multicast_rate
      bc_filter_enabled    = v.bc_filter_enabled
      site                 = v.site
    }
  }
}