# UniFi WLANs Module - Main Configuration

# UniFi WLAN Resources
resource "unifi_wlan" "this" {
  for_each = var.wlans

  name       = each.value.name
  network_id = each.value.network_id
  site       = coalesce(each.value.site, var.site)

  # Security Configuration
  security        = coalesce(each.value.security, var.default_security)
  passphrase      = each.value.passphrase
  wpa3_support    = coalesce(each.value.wpa3_support, var.default_wpa3_support)
  wpa3_transition = coalesce(each.value.wpa3_transition, var.default_wpa3_transition)
  pmf_mode        = coalesce(each.value.pmf_mode, var.default_pmf_mode)

  # Guest Network Configuration
  is_guest      = each.value.is_guest
  user_group_id = each.value.user_group_id

  # SSID Visibility and Access Control
  hide_ssid          = each.value.hide_ssid
  mac_filter_enabled = each.value.mac_filter_enabled
  mac_filter_policy  = each.value.mac_filter_policy
  mac_filter_list    = each.value.mac_filter_list

  # Enterprise Authentication
  radius_profile_id = each.value.radius_profile_id

  # Scheduling
  schedule = each.value.schedule

  # Quality of Service and Performance
  uapsd             = coalesce(each.value.uapsd, var.enable_uapsd)
  dtim_mode         = each.value.dtim_mode
  dtim_na           = each.value.dtim_na
  dtim_ng           = each.value.dtim_ng
  multicast_enhance = each.value.multicast_enhance

  # Advanced Wireless Features
  no2ghz_oui           = each.value.no2ghz_oui
  proxy_arp            = each.value.is_guest ? var.guest_proxy_arp : each.value.proxy_arp
  l2_isolation         = each.value.is_guest ? var.guest_network_isolation : each.value.l2_isolation
  bss_transition       = coalesce(each.value.bss_transition, var.enable_bss_transition)
  fast_roaming_enabled = coalesce(each.value.fast_roaming_enabled, var.enable_fast_roaming)

  # Hotspot 2.0
  hotspot2_conf = each.value.hotspot2_conf

  # Band Configuration
  wlan_band = coalesce(each.value.wlan_band, var.default_wlan_band)

  # Access Point Group Assignment
  ap_group_ids  = each.value.ap_group_ids
  ap_group_mode = each.value.ap_group_mode

  # Data Rate Configuration
  minimum_data_rate_2g = coalesce(each.value.minimum_data_rate_2g, var.default_minimum_data_rate_2g)
  minimum_data_rate_5g = coalesce(each.value.minimum_data_rate_5g, var.default_minimum_data_rate_5g)
  minimum_data_rate_6g = coalesce(each.value.minimum_data_rate_6g, var.default_minimum_data_rate_6g)
  multicast_rate       = coalesce(each.value.multicast_rate, var.default_multicast_rate)

  # Broadcast Filtering
  bc_filter_enabled = each.value.bc_filter_enabled
  bc_filter_list    = each.value.bc_filter_list

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Local values for WLAN organization and validation
locals {
  # Organize WLANs by type for easier management
  guest_wlans = {
    for k, v in var.wlans : k => v
    if v.is_guest == true
  }

  secure_wlans = {
    for k, v in var.wlans : k => v
    if v.is_guest != true
  }

  # WLANs with enterprise authentication
  enterprise_wlans = {
    for k, v in var.wlans : k => v
    if v.radius_profile_id != null
  }

  # WLANs with MAC filtering enabled
  mac_filtered_wlans = {
    for k, v in var.wlans : k => v
    if v.mac_filter_enabled == true
  }

  # WLANs with scheduling enabled
  scheduled_wlans = {
    for k, v in var.wlans : k => v
    if length(v.schedule) > 0
  }

  # WLANs by band configuration
  dual_band_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.wlan_band, var.default_wlan_band) == "both"
  }

  single_band_2g_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.wlan_band, var.default_wlan_band) == "2g"
  }

  single_band_5g_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.wlan_band, var.default_wlan_band) == "5g"
  }

  single_band_6g_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.wlan_band, var.default_wlan_band) == "6g"
  }

  # WLANs with WPA3 support
  wpa3_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.wpa3_support, var.default_wpa3_support) == true
  }

  # WLANs with fast roaming enabled
  fast_roaming_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.fast_roaming_enabled, var.enable_fast_roaming) == true
  }

  # WLANs with BSS transition enabled
  bss_transition_wlans = {
    for k, v in var.wlans : k => v
    if coalesce(v.bss_transition, var.enable_bss_transition) == true
  }

  # Security mode validation
  valid_security_modes = ["open", "wpapsk", "wpaeap", "wpa3sae", "wpa3eap192", "wpa3eap"]

  # Validate security modes
  invalid_security_wlans = {
    for k, v in var.wlans : k => v
    if !contains(local.valid_security_modes, coalesce(v.security, var.default_security))
  }
}

# Validation checks
resource "null_resource" "validate_security_modes" {
  count = length(local.invalid_security_wlans) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: Invalid security modes found in WLANs: ${join(", ", keys(local.invalid_security_wlans))}' && exit 1"
  }
}

# Data source for network validation (optional - helps catch configuration errors early)
data "unifi_network" "validation" {
  for_each = var.wlans
  id       = each.value.network_id
  site     = coalesce(each.value.site, var.site)
}