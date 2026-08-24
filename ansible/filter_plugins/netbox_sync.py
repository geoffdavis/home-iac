"""Filter plugins backing the NetBox -> UDM sync roles
(unifi_network_dns_record, unifi_network_ip_reservation).

Why plain Python instead of nested Jinja in the role tasks: the design
doc (docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md, "Sync
direction and idempotency") requires a *full, symmetric set comparison*
between NetBox's desired state and the UDM's current state, plus an
ownership-exclusion filter for external-dns-managed records. That logic
needs to be exercised directly by pytest, not rendered through Ansible's
Templar -- so it lives here, unit-tested in
ansible/tests/unit/test_netbox_sync_filters.py, and the role tasks call
it as filters. The per-record create/update/no-op logic in each role's
reconcile_one.yml is deliberately left as ordinary Jinja, unchanged in
shape from the ugreen-nas-compose original (spec: "UDM-side diff/PUT
logic unchanged").
"""

from __future__ import annotations

import re

_MAC_RE = re.compile(r"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$")


def _dns_id(record):
    return (record.get("record_type"), record.get("key"))


def dns_external_dns_owned_keys(existing_records, heritage_marker):
    """Return the sorted set of `key`s the UDM's current static-DNS list
    marks as owned by external-dns: any TXT record whose value contains
    `heritage_marker` (external-dns's TXT-registry ownership convention,
    default "heritage=external-dns").

    NOT VERIFIED against a live controller yet -- pi-talos-home-ops's
    actual --txt-owner-id / TXT-registry naming needs confirming against
    a real UDM static-DNS dump before this is trusted in production. See
    the role README's "Known gaps" section.
    """
    return sorted(
        {
            r["key"]
            for r in existing_records
            if r.get("record_type") == "TXT" and heritage_marker in (r.get("value") or "")
        }
    )


def dns_in_zone(records, zone_suffix):
    """Records whose `key` is the zone apex or a subdomain of it.

    Dot-aware suffix match -- "geoffdavis.com" must not match
    "evilgeoffdavis.com".
    """
    suffix = zone_suffix.lstrip(".")
    return [r for r in records if r.get("key") == suffix or r.get("key", "").endswith("." + suffix)]


def dns_exclude_owned(records, excluded_keys):
    """Drop any record whose key is in excluded_keys (the external-dns
    ownership exclusion set) -- applied to BOTH set A and set B before
    they're compared, so an external-dns-owned name is invisible to this
    sync in either direction (never proposed as a create/update, never
    reported as an orphan)."""
    excluded = set(excluded_keys)
    return [r for r in records if r.get("key") not in excluded]


def dns_orphans(current_records, desired_records):
    """set B (current UDM state, already zone-filtered + ownership-
    excluded) minus set A (NetBox desired state) -- the case a
    walk-only-the-desired-list reconciler misses entirely (design doc,
    "Sync direction and idempotency", point 3). Never auto-deleted; the
    caller logs these loudly."""
    desired_ids = {_dns_id(r) for r in desired_records}
    return [r for r in current_records if _dns_id(r) not in desired_ids]


def netbox_dns_records_to_udm(netbox_records, zone_name):
    """Transform netbox-dns plugin record objects into this repo's UDM
    static-DNS record-dict shape: {record_type, key, value, enabled,
    state}.

    netbox-dns records carry a zone-relative `name` ("@" for the apex,
    otherwise a label/sub-label with no trailing zone) plus `type`,
    `value`, and `status` ("active"/"inactive", among others -- only
    "active" maps to enabled=true, everything else is treated as
    disabled rather than dropped, so a NetBox-side pause doesn't have to
    round-trip through delete+recreate).

    This is the DNS-plugin shape the spec leaves as an
    implementation-time decision (Open Questions: "Which plugin...
    verify it's still maintained... before committing"). If netbox-dns
    turns out unavailable on the deployed NetBox version, the spec's
    documented fallback is ipam.IPAddress's built-in dns_name field
    (A/AAAA only) -- that would need its own transform function here,
    not a variant of this one, since the source shape is unrelated.
    """
    out = []
    for rec in netbox_records:
        name = rec.get("name", "@")
        key = zone_name if name in ("@", "", None) else f"{name}.{zone_name}"
        out.append(
            {
                "record_type": rec["type"],
                "key": key,
                "value": rec["value"],
                "enabled": rec.get("status") == "active",
                "state": "present",
            }
        )
    return out


def normalize_mac(mac):
    """Lowercase, colon-separated MAC, or None if absent/malformed.
    UDM's legacy REST `user` objects key reservations on MAC in this
    form; NetBox interfaces may return mac_address in mixed case."""
    if not mac:
        return None
    mac = mac.strip()
    if not _MAC_RE.match(mac):
        return None
    return mac.lower()


def netbox_ip_to_reservation(ip_obj):
    """Transform one NetBox ipam.IPAddress object (status=dhcp) into a
    {ip, mac, hostname} draft reservation. `mac` is None when the
    address has no assigned interface or the interface has no
    mac_address -- callers must skip-and-warn on that, never guess a
    MAC. VLAN/network-name resolution is NOT done here (it requires a
    second NetBox lookup for the containing prefix and a live UDM
    networkconf lookup) -- that stays in the role's tasks, which then
    call reservation_ready() below on the result.
    """
    address = ip_obj.get("address", "")
    ip = address.split("/", 1)[0] if address else None
    assigned = ip_obj.get("assigned_object") or {}
    mac = normalize_mac(assigned.get("mac_address"))
    return {
        "ip": ip,
        "mac": mac,
        "hostname": ip_obj.get("dns_name") or None,
        "netbox_id": ip_obj.get("id"),
    }


def reservation_ready(reservation):
    """True if a draft reservation has enough to push to the UDM (ip +
    mac). Missing-MAC / missing-IP entries must be skipped with a loud
    warning, never silently dropped -- the caller logs what
    reservation_missing() reports below."""
    return bool(reservation.get("ip")) and bool(reservation.get("mac"))


def reservation_missing(reservations):
    """The subset of draft reservations reservation_ready() rejects, for
    the role to log loudly (never a silent skip)."""
    return [r for r in reservations if not reservation_ready(r)]


class FilterModule:
    def filters(self):
        return {
            "dns_external_dns_owned_keys": dns_external_dns_owned_keys,
            "dns_in_zone": dns_in_zone,
            "dns_exclude_owned": dns_exclude_owned,
            "dns_orphans": dns_orphans,
            "netbox_dns_records_to_udm": netbox_dns_records_to_udm,
            "normalize_mac": normalize_mac,
            "netbox_ip_to_reservation": netbox_ip_to_reservation,
            "reservation_ready": reservation_ready,
            "reservation_missing": reservation_missing,
        }
