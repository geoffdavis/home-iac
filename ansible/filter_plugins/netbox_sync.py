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

Scope note: netbox_dns_records_to_udm is the source transform here,
reading the netbox-dns plugin's own Record objects. An earlier version
of this sync (PR #16 as originally shipped) targeted
ipam.IPAddress.dns_name instead -- the spec's documented FALLBACK, used
only because netbox-dns wasn't installed at the time (confirmed live
2026-08-24: GET /api/status/ returned "plugins":{}). Plan Task 8
installed the plugin and backfilled real Record data (2026-08-26,
ansible/roles/netbox_import_udm_dns_records/), which is what this
transform reads from now -- see Task 8 Step 4 in
docs/superpowers/plans/2026-08-21-netbox-udm-sync.md. The ipam.IPAddress
fallback (netbox_ipaddress_dns_records_to_udm) is gone: it was A/AAAA
only and could never represent nas-sdg's real CNAME, wildcard, and
split-horizon (non-IPAM) records, which is exactly what this rework
fixes.
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


def netbox_dns_records_to_udm(records):
    """Transform netbox-dns plugin `Record` objects (GET
    /api/plugins/netbox-dns/records/) into this repo's UDM static-DNS
    record-dict shape ({record_type, key, value, enabled, state}).

    Supersedes netbox_ipaddress_dns_records_to_udm (the ipam.IPAddress
    fallback PR #16 originally shipped) now that the netbox-dns plugin
    is installed and populated with real data (plan Task 8). netbox-dns
    models DNS records as first-class Record objects -- arbitrary
    `type`, arbitrary string `value`, not derived from an IP address --
    which removes the fallback's structural gaps: CNAME, NS, wildcard
    (`*.`) names, and split-horizon values with no IPAM presence (e.g.
    the netbird-overlay A records pointing at 100.92.233.103) all
    transform cleanly here, where the fallback simply could not
    represent them.

    Empirical facts this transform relies on -- verified live against
    the real API (2026-08-26; see
    ansible/roles/netbox_import_udm_dns_records/README.md's "Empirical
    API-shape findings" for the backfill role's matching write-path
    findings, re-confirmed independently here for the read path):

    - `fqdn` is a real, server-computed, trailing-dot FQDN (e.g.
      "*.admin.home.geoffdavis.com.", and "home.geoffdavis.com." for
      the zone apex, whose relative `name` is the literal string "@") --
      used directly here (dot stripped) rather than reconstructed from
      `name` + a zone-suffix string, since the server already handles
      the apex/wildcard cases correctly and reconstructing it
      independently would just be duplicating that logic with a second
      chance to get it wrong.
    - `value` for a name-shaped record (CNAME/NS/MX) carries a trailing
      dot (netbox-dns's own FQDN convention); the UDM's static-DNS
      `value` field does not (see the example in
      ansible/roles/unifi_network_dns_record/README.md and
      host_vars/nas-sdg.yml's syslog CNAME) -- stripped here
      unconditionally. A/AAAA values are IP literals and never carry a
      trailing dot, so unconditional stripping is safe for every
      record_type.
    - `status` serializes as a **plain string** ("active"), NOT the
      nested {value, label} choice shape ipam.IPAddress's `status` field
      uses -- the exact bug netbox_import_udm_dns_records's
      reconcile_one.yml hit (and fixed) on its own idempotent re-run.
      Compared directly here as a string, no `.value`.
    - `managed` (bool) marks netbox-dns's own auto-generated
      zone-bookkeeping records -- the zone's SOA and its apex NS
      (confirmed live: both carry managed=true on this zone; every
      real, UDM-sourced record carries managed=false). These have no
      UDM static-DNS equivalent (the UDM's static-DNS feature has no
      SOA record type, and the apex NS is bookkeeping-only per plan
      Task 8 Step 2's zone-creation notes -- "nothing queries it as a
      real NS") and are unconditionally skipped here.
    """
    out = []
    for record in records:
        if record.get("managed"):
            continue
        fqdn = record.get("fqdn") or ""
        key = fqdn[:-1] if fqdn.endswith(".") else fqdn
        if not key:
            continue
        value = record.get("value") or ""
        if value.endswith("."):
            value = value[:-1]
        out.append(
            {
                "record_type": record.get("type"),
                "key": key,
                "value": value,
                "enabled": record.get("status") == "active",
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
            "netbox_dns_records_to_udm": netbox_dns_records_to_udm,
        }
