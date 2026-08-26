"""Filter plugins backing the NetBox -> UDM DNS sync
(unifi_network_dns_record).

Why plain Python instead of nested Jinja in the role tasks: the design
doc (docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md, "Sync
direction and idempotency") requires a *full, symmetric set comparison*
between NetBox's desired state and the UDM's current state, plus an
ownership-exclusion filter for external-dns-managed records. That logic
needs to be exercised directly by pytest, not rendered through Ansible's
Templar -- so it lives here, unit-tested in
ansible/tests/unit/test_netbox_sync_filters.py, and the role tasks call
it as filters. The per-record create/update/no-op logic in
reconcile_one.yml is deliberately left as ordinary Jinja, unchanged in
shape from the ugreen-nas-compose original (spec: "UDM-side diff/PUT
logic unchanged").

Scope note: netbox_ipaddress_dns_records_to_udm is the ONLY source
transform here. An earlier draft of this sync targeted the netbox-dns
plugin's own record objects -- dropped after confirming live 2026-08-24
(GET /api/status/ on the running instance: "plugins":{}) that no
DNS plugin is installed, so the spec's documented fallback
(ipam.IPAddress's built-in dns_name field) is what this fleet actually
has to sync from, not an implementation-time choice still open.
"""

from __future__ import annotations

import re

# external-dns's TXT-registry ownership records aren't named identically
# to the record they protect -- this fleet's external-dns is configured
# with a "_externaldns." txt-prefix AND a record-type infix to avoid
# colliding with other TXT records on the same name, so the *protected*
# name is embedded as "_externaldns.<type>-<name>", e.g.
# "_externaldns.a-hubble.k8s.home.geoffdavis.com" protects
# "hubble.k8s.home.geoffdavis.com". Confirmed live 2026-08-25 (Task 3
# dry-run against nas-sdg/UDM): an earlier version of this function
# returned the TXT record's own key unmodified, which silently excluded
# nothing real (the exclusion set and the A/AAAA keys it was meant to
# match never had a single string in common) and let
# website-dev.k8s/website-prod.k8s/hubble.k8s -- the exact
# external-dns-owned names this filter exists to protect -- show up as
# orphans. Only decode the prefix when present; a TXT record whose key
# already equals the protected name (a simpler registry config with no
# prefix) is left as-is.
_EXTERNAL_DNS_TXT_PREFIX = "_externaldns."
_EXTERNAL_DNS_TXT_TYPE_INFIX_RE = re.compile(r"^(?:a|aaaa|cname|txt|mx|ns|srv|ptr|ds|naptr|caa)-")


def _dns_id(record):
    return (record.get("record_type"), record.get("key"))


def dns_external_dns_owned_keys(existing_records, heritage_marker):
    """Return the sorted set of record `key`s the UDM's current
    static-DNS list marks as owned by external-dns: decoded from any TXT
    record whose value contains `heritage_marker` (external-dns's
    TXT-registry ownership convention, default "heritage=external-dns").

    Includes BOTH the protected name (e.g.
    "hubble.k8s.home.geoffdavis.com") AND the TXT registry record's own
    literal key (e.g.
    "_externaldns.a-hubble.k8s.home.geoffdavis.com") -- the registry
    record itself is Kubernetes-managed bookkeeping too, and without
    excluding its own key it shows up as a false-positive "orphan" every
    single run (this sync's A/AAAA-only NetBox source has no way to
    represent a TXT record, so it can never match one). Live finding
    2026-08-25 (Task 3 dry run): the first version of this function
    excluded only the decoded name and left the registry record itself
    flagged as noise.

    Confirmed live 2026-08-24 (Task 2 backfill investigation) that this
    marker correctly identifies the TXT records for
    website-dev.k8s.home.geoffdavis.com,
    website-prod.k8s.home.geoffdavis.com and
    hubble.k8s.home.geoffdavis.com; confirmed live 2026-08-25 (Task 3
    dry run) that recovering the *protected* name requires decoding the
    "_externaldns.<type>-" prefix those TXT records' own keys carry --
    see module docstring above.
    """
    owned = set()
    for r in existing_records:
        if r.get("record_type") != "TXT" or heritage_marker not in (r.get("value") or ""):
            continue
        key = r.get("key") or ""
        owned.add(key)
        if key.startswith(_EXTERNAL_DNS_TXT_PREFIX):
            decoded = _EXTERNAL_DNS_TXT_TYPE_INFIX_RE.sub("", key[len(_EXTERNAL_DNS_TXT_PREFIX) :])
            owned.add(decoded)
    return sorted(owned)


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


# NetBox ipam.IPAddress `status` values (confirmed live 2026-08-24 via
# OPTIONS on /api/ipam/ip-addresses/: active, reserved, deprecated, dhcp,
# slaac -- no "inactive"/"disabled" choice exists) that should still sync
# but as a disabled record, mirroring the netbox-dns-plugin design's
# active/inactive distinction for a status this data model doesn't have
# a record-level flag for.
_DISABLED_STATUSES = {"deprecated"}


def netbox_ipaddress_dns_records_to_udm(ip_addresses):
    """Transform NetBox ipam.IPAddress objects into this repo's UDM
    static-DNS record-dict shape ({record_type, key, value, enabled,
    state}) -- the spec's documented fallback data model (Open
    Questions: "if [netbox-dns] isn't [installed]... the documented
    fallback is ipam.IPAddress's built-in dns_name field, A/AAAA only").

    A/AAAA only, by construction: an IP address can only ever represent
    itself, so CNAME/NS/MX/TXT records this fleet's UDM also carries
    (see the role README) have no home in this data model and are
    simply invisible to this sync, not an error. record_type comes from
    NetBox's own `family.value` (4 or 6), not guessed from string shape.
    Addresses with no dns_name are silently skipped -- nothing to sync.
    status=deprecated maps to enabled=False (synced, but disabled on the
    UDM) rather than dropped, mirroring how the netbox-dns-plugin design
    this replaced treated its own "inactive" status.
    """
    out = []
    for ip_obj in ip_addresses:
        dns_name = ip_obj.get("dns_name")
        if not dns_name:
            continue
        address = ip_obj.get("address") or ""
        bare_ip = address.split("/", 1)[0] if address else None
        if not bare_ip:
            continue
        family = ip_obj.get("family") or {}
        family_value = family.get("value") if isinstance(family, dict) else family
        record_type = "AAAA" if family_value == 6 else "A"
        status = ip_obj.get("status") or {}
        status_value = status.get("value") if isinstance(status, dict) else status
        out.append(
            {
                "record_type": record_type,
                "key": dns_name,
                "value": bare_ip,
                "enabled": status_value not in _DISABLED_STATUSES,
                "state": "present",
            }
        )
    return out


class FilterModule:
    def filters(self):
        return {
            "dns_external_dns_owned_keys": dns_external_dns_owned_keys,
            "dns_in_zone": dns_in_zone,
            "dns_exclude_owned": dns_exclude_owned,
            "dns_orphans": dns_orphans,
            "netbox_ipaddress_dns_records_to_udm": netbox_ipaddress_dns_records_to_udm,
        }
