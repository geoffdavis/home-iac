# UniFi WLANs Configuration for Dev Environment

# UniFi WLANs Module
module "unifi_wlans" {
  source = "../../modules/unifi-wlans"

  site        = var.unifi_site
  common_tags = local.common_tags

  # Default security and performance settings
  default_security             = "wpapsk"
  default_wpa3_support         = true
  default_wpa3_transition      = true
  default_pmf_mode             = "optional"
  default_wlan_band            = "both"
  default_minimum_data_rate_2g = 1000 # 1 Mbps
  default_minimum_data_rate_5g = 6000 # 6 Mbps
  default_minimum_data_rate_6g = 6000 # 6 Mbps
  default_multicast_rate       = 6000 # 6 Mbps
  enable_fast_roaming          = true
  enable_bss_transition        = true
  enable_uapsd                 = true
  guest_network_isolation      = true
  guest_proxy_arp              = true

  wlans = {
    # Main/Trusted Network SSID - Connected to Main LAN (VLAN 1)
    main_wifi = {
      name                 = "HomeNetwork"
      network_id           = module.unifi_networks.network_ids["main_lan"]
      passphrase           = var.main_wifi_passphrase
      security             = "wpapsk"
      wpa3_support         = true
      wpa3_transition      = true
      pmf_mode             = "optional"
      is_guest             = false
      hide_ssid            = false
      wlan_band            = "both"
      fast_roaming_enabled = true
      bss_transition       = true
      uapsd                = true
      multicast_enhance    = true
      proxy_arp            = false
      l2_isolation         = false
      minimum_data_rate_2g = 1000
      minimum_data_rate_5g = 6000
      minimum_data_rate_6g = 6000
      multicast_rate       = 6000
    }

    # Guest Network SSID - Connected to Guest VLAN (VLAN 10)
    guest_wifi = {
      name                 = "HomeGuest"
      network_id           = module.unifi_networks.network_ids["guest"]
      passphrase           = var.guest_wifi_passphrase
      security             = "wpapsk"
      wpa3_support         = true
      wpa3_transition      = true
      pmf_mode             = "optional"
      is_guest             = true
      hide_ssid            = false
      wlan_band            = "both"
      fast_roaming_enabled = false # Disable for guest network
      bss_transition       = false # Disable for guest network
      uapsd                = false # Disable for guest network
      multicast_enhance    = false
      proxy_arp            = true # Enable for guest isolation
      l2_isolation         = true # Enable for guest isolation
      minimum_data_rate_2g = 1000
      minimum_data_rate_5g = 6000
      minimum_data_rate_6g = 6000
      multicast_rate       = 1000 # Lower for guest network
      bc_filter_enabled    = true
      bc_filter_list       = ["arp", "dhcp", "netbios"]
    }

    # IoT Devices SSID - Connected to IoT VLAN (VLAN 20)
    iot_wifi = {
      name                 = "HomeIoT"
      network_id           = module.unifi_networks.network_ids["iot"]
      passphrase           = var.iot_wifi_passphrase
      security             = "wpapsk"
      wpa3_support         = false # Some IoT devices don't support WPA3
      wpa3_transition      = false
      pmf_mode             = "disabled" # Some IoT devices have issues with PMF
      is_guest             = false
      hide_ssid            = true # Hide IoT network
      wlan_band            = "both"
      fast_roaming_enabled = false # IoT devices often don't support 802.11r
      bss_transition       = false # IoT devices often don't support 802.11v
      uapsd                = false # Disable for IoT compatibility
      multicast_enhance    = true  # Enable for IoT multicast traffic
      proxy_arp            = false
      l2_isolation         = false
      minimum_data_rate_2g = 1000 # Keep low for older IoT devices
      minimum_data_rate_5g = 6000
      minimum_data_rate_6g = 6000
      multicast_rate       = 1000 # Lower for IoT compatibility
    }

    # Management SSID - Connected to Management VLAN (VLAN 30)
    management_wifi = {
      name                 = "HomeMgmt"
      network_id           = module.unifi_networks.network_ids["management"]
      passphrase           = var.management_wifi_passphrase
      security             = "wpapsk"
      wpa3_support         = true
      wpa3_transition      = true
      pmf_mode             = "required" # Require PMF for management network
      is_guest             = false
      hide_ssid            = true # Hide management network
      wlan_band            = "both"
      fast_roaming_enabled = true
      bss_transition       = true
      uapsd                = true
      multicast_enhance    = false
      proxy_arp            = false
      l2_isolation         = false
      minimum_data_rate_2g = 6000  # Higher minimum for management
      minimum_data_rate_5g = 12000 # Higher minimum for management
      minimum_data_rate_6g = 12000 # Higher minimum for management
      multicast_rate       = 12000 # Higher for management network
      mac_filter_enabled   = var.enable_management_mac_filtering
      mac_filter_policy    = "allow"
      mac_filter_list      = var.management_allowed_macs
      schedule             = var.management_wifi_schedule
    }

    # High-Performance 5GHz Network for demanding devices
    performance_5g = {
      name                 = "HomePerformance"
      network_id           = module.unifi_networks.network_ids["main_lan"]
      passphrase           = var.performance_wifi_passphrase
      security             = "wpapsk"
      wpa3_support         = true
      wpa3_transition      = true
      pmf_mode             = "optional"
      is_guest             = false
      hide_ssid            = false
      wlan_band            = "5g" # 5GHz only for performance
      fast_roaming_enabled = true
      bss_transition       = true
      uapsd                = true
      multicast_enhance    = true
      proxy_arp            = false
      l2_isolation         = false
      minimum_data_rate_2g = 0     # Not applicable for 5GHz only
      minimum_data_rate_5g = 24000 # High minimum rate for performance
      minimum_data_rate_6g = 24000 # High minimum rate for performance
      multicast_rate       = 24000 # High multicast rate
      dtim_mode            = "custom"
      dtim_na              = 1 # Optimize for performance
      dtim_ng              = 1 # Optimize for performance
    }

    # Legacy 2.4GHz Network for older devices
    legacy_24g = {
      name                 = "HomeLegacy"
      network_id           = module.unifi_networks.network_ids["iot"]
      passphrase           = var.legacy_wifi_passphrase
      security             = "wpapsk"
      wpa3_support         = false # Legacy devices don't support WPA3
      wpa3_transition      = false
      pmf_mode             = "disabled" # Legacy devices don't support PMF
      is_guest             = false
      hide_ssid            = true  # Hide legacy network
      wlan_band            = "2g"  # 2.4GHz only for legacy devices
      fast_roaming_enabled = false # Legacy devices don't support 802.11r
      bss_transition       = false # Legacy devices don't support 802.11v
      uapsd                = false # Disable for legacy compatibility
      multicast_enhance    = false
      proxy_arp            = false
      l2_isolation         = false
      minimum_data_rate_2g = 1000 # Very low for legacy devices
      minimum_data_rate_5g = 0    # Not applicable for 2.4GHz only
      minimum_data_rate_6g = 0    # Not applicable for 2.4GHz only
      multicast_rate       = 1000 # Low for legacy compatibility
      dtim_mode            = "default"
      dtim_na              = 3 # Higher DTIM for legacy power saving
      dtim_ng              = 3 # Higher DTIM for legacy power saving
    }
  }

  # Dependency on networks module
  depends_on = [module.unifi_networks]
}

# Outputs for WLAN information
output "unifi_wlan_summary" {
  description = "Summary of UniFi WLANs created"
  value       = module.unifi_wlans.wlan_summary
}

output "unifi_wlan_ids" {
  description = "Map of WLAN names to IDs"
  value       = module.unifi_wlans.wlan_ids
}

output "unifi_guest_wlans" {
  description = "Guest WLAN configurations"
  value       = module.unifi_wlans.guest_wlans
}

output "unifi_secure_wlans" {
  description = "Secure WLAN configurations"
  value       = module.unifi_wlans.secure_wlans
}

output "unifi_wlan_band_distribution" {
  description = "Distribution of WLANs by band"
  value       = module.unifi_wlans.wlan_band_distribution
}

output "unifi_wlan_security_distribution" {
  description = "Distribution of WLANs by security features"
  value       = module.unifi_wlans.wlan_security_distribution
}

output "unifi_wlan_performance_settings" {
  description = "WLAN performance and QoS settings"
  value       = module.unifi_wlans.wlan_performance_settings
  sensitive   = false
}