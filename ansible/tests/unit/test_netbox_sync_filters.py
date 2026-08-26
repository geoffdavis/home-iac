"""Unit tests for filter_plugins/netbox_sync.py — the full symmetric-set
comparison, external-dns ownership exclusion, and the NetBox->UDM record
transform the design doc requires
(docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md, "Sync
direction and idempotency" + "Ownership filter").

Plain Python, no Ansible/Templar involved — these functions are called
as Jinja filters from the role tasks, but the logic itself is ordinary
Python and is tested as such.
"""

from filter_plugins.netbox_sync import (
    dns_exclude_owned,
    dns_external_dns_owned_keys,
    dns_in_zone,
    dns_orphans,
    netbox_ipaddress_dns_records_to_udm,
)

# ── dns_external_dns_owned_keys ─────────────────────────────────────────


def test_owned_keys_finds_txt_heritage_marker():
    """Simple registry config: TXT record key equals the protected name
    verbatim (no txt-prefix, no type infix) -- left as-is."""
    existing = [
        {"record_type": "A", "key": "app.k8s.home.geoffdavis.com", "value": "172.29.1.1"},
        {
            "record_type": "TXT",
            "key": "app.k8s.home.geoffdavis.com",
            "value": '"heritage=external-dns,external-dns/owner=pi-talos-home-ops"',
        },
    ]
    assert dns_external_dns_owned_keys(existing, "heritage=external-dns") == [
        "app.k8s.home.geoffdavis.com"
    ]


def test_owned_keys_decodes_externaldns_prefix_and_type_infix():
    """This fleet's actual registry config (confirmed live 2026-08-25):
    txt-prefix "_externaldns." plus a "<type>-" infix to avoid TXT-name
    collisions, e.g. "_externaldns.a-hubble.k8s.home.geoffdavis.com"
    protects "hubble.k8s.home.geoffdavis.com", not a name matching its
    own literal key. Both the decoded protected name AND the registry
    record's own key are returned -- the registry record itself must
    also be excluded from set B, or it shows up as a false orphan every
    run (this sync's A/AAAA-only source can never match a TXT record)."""
    existing = [
        {"record_type": "A", "key": "hubble.k8s.home.geoffdavis.com", "value": "172.29.55.0"},
        {
            "record_type": "TXT",
            "key": "_externaldns.a-hubble.k8s.home.geoffdavis.com",
            "value": '"heritage=external-dns,external-dns/owner=pi-talos-home-ops"',
        },
    ]
    assert dns_external_dns_owned_keys(existing, "heritage=external-dns") == [
        "_externaldns.a-hubble.k8s.home.geoffdavis.com",
        "hubble.k8s.home.geoffdavis.com",
    ]


def test_owned_keys_ignores_unrelated_txt():
    existing = [{"record_type": "TXT", "key": "spf.home.geoffdavis.com", "value": "v=spf1 -all"}]
    assert dns_external_dns_owned_keys(existing, "heritage=external-dns") == []


def test_owned_keys_ignores_non_txt_records():
    existing = [{"record_type": "A", "key": "x.home.geoffdavis.com", "value": "heritage=external-dns"}]
    assert dns_external_dns_owned_keys(existing, "heritage=external-dns") == []


# ── dns_in_zone ──────────────────────────────────────────────────────────


def test_in_zone_matches_apex_and_subdomain():
    records = [
        {"key": "home.geoffdavis.com"},
        {"key": "syslog.home.geoffdavis.com"},
        {"key": "other.example.com"},
    ]
    result = dns_in_zone(records, "home.geoffdavis.com")
    assert {r["key"] for r in result} == {"home.geoffdavis.com", "syslog.home.geoffdavis.com"}


def test_in_zone_does_not_match_lookalike_suffix():
    """'geoffdavis.com' must not match 'evilgeoffdavis.com' — a naive
    str.endswith(suffix) without the dot-boundary check would."""
    records = [{"key": "evilgeoffdavis.com"}]
    assert dns_in_zone(records, "geoffdavis.com") == []


# ── dns_exclude_owned / dns_orphans ─────────────────────────────────────


def test_exclude_owned_drops_matching_keys():
    records = [{"key": "a.home.geoffdavis.com"}, {"key": "b.home.geoffdavis.com"}]
    assert dns_exclude_owned(records, ["a.home.geoffdavis.com"]) == [
        {"key": "b.home.geoffdavis.com"}
    ]


def test_orphans_finds_records_only_in_current():
    current = [
        {"record_type": "A", "key": "a.home.geoffdavis.com", "value": "1.1.1.1"},
        {"record_type": "A", "key": "orphan.home.geoffdavis.com", "value": "2.2.2.2"},
    ]
    desired = [{"record_type": "A", "key": "a.home.geoffdavis.com", "value": "1.1.1.1"}]
    orphans = dns_orphans(current, desired)
    assert [o["key"] for o in orphans] == ["orphan.home.geoffdavis.com"]


def test_orphans_distinguishes_by_record_type_not_just_key():
    """The same key with a different record_type in 'desired' must not
    mask an orphan of the type actually missing (design doc: identity is
    key + record_type)."""
    current = [
        {"record_type": "A", "key": "x.home.geoffdavis.com", "value": "1.1.1.1"},
        {"record_type": "TXT", "key": "x.home.geoffdavis.com", "value": "v=1"},
    ]
    desired = [{"record_type": "A", "key": "x.home.geoffdavis.com", "value": "1.1.1.1"}]
    orphans = dns_orphans(current, desired)
    assert [(o["record_type"], o["key"]) for o in orphans] == [("TXT", "x.home.geoffdavis.com")]


def test_orphans_empty_when_sets_match():
    current = [{"record_type": "A", "key": "a.home.geoffdavis.com", "value": "1.1.1.1"}]
    desired = [{"record_type": "A", "key": "a.home.geoffdavis.com", "value": "1.1.1.1"}]
    assert dns_orphans(current, desired) == []


# ── netbox_ipaddress_dns_records_to_udm ─────────────────────────────────


def test_transform_ipv4_record():
    ip_addresses = [
        {
            "address": "172.29.50.20/24",
            "dns_name": "media.home.geoffdavis.com",
            "family": {"value": 4},
            "status": {"value": "active"},
        }
    ]
    result = netbox_ipaddress_dns_records_to_udm(ip_addresses)
    assert result == [
        {
            "record_type": "A",
            "key": "media.home.geoffdavis.com",
            "value": "172.29.50.20",
            "enabled": True,
            "state": "present",
        }
    ]


def test_transform_ipv6_record_uses_aaaa():
    ip_addresses = [
        {
            "address": "fd47:25e1:2f96:50::20/64",
            "dns_name": "media6.home.geoffdavis.com",
            "family": {"value": 6},
            "status": {"value": "active"},
        }
    ]
    result = netbox_ipaddress_dns_records_to_udm(ip_addresses)
    assert result[0]["record_type"] == "AAAA"
    assert result[0]["value"] == "fd47:25e1:2f96:50::20"


def test_transform_deprecated_status_is_disabled_not_dropped():
    ip_addresses = [
        {
            "address": "172.29.50.99/24",
            "dns_name": "old.home.geoffdavis.com",
            "family": {"value": 4},
            "status": {"value": "deprecated"},
        }
    ]
    result = netbox_ipaddress_dns_records_to_udm(ip_addresses)
    assert len(result) == 1
    assert result[0]["enabled"] is False


def test_transform_skips_addresses_with_no_dns_name():
    ip_addresses = [
        {"address": "172.29.50.1/24", "dns_name": "", "family": {"value": 4}, "status": {"value": "active"}},
        {"address": "172.29.50.2/24", "dns_name": None, "family": {"value": 4}, "status": {"value": "active"}},
    ]
    assert netbox_ipaddress_dns_records_to_udm(ip_addresses) == []


def test_transform_strips_cidr_mask():
    ip_addresses = [
        {
            "address": "172.29.10.31/24",
            "dns_name": "pacificbeach.mgmt.home.geoffdavis.com",
            "family": {"value": 4},
            "status": {"value": "active"},
        }
    ]
    result = netbox_ipaddress_dns_records_to_udm(ip_addresses)
    assert result[0]["value"] == "172.29.10.31"
