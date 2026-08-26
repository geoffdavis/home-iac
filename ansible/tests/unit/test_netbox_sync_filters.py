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
    netbox_dns_records_to_udm,
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


# ── netbox_dns_records_to_udm ───────────────────────────────────────────
#
# Fixtures below mirror the real, live-verified shape of netbox-dns
# Record objects (GET /api/plugins/netbox-dns/records/, confirmed
# 2026-08-26 against nas-sdg's real home.geoffdavis.com zone) — not a
# guessed schema. In particular: `status` is a plain string (not the
# nested {value, label} shape ipam.IPAddress used), `fqdn` is a real,
# server-computed, trailing-dot field, and `managed` is present and
# boolean on every record (true only for the zone's own auto-generated
# SOA/apex-NS bookkeeping).


def test_transform_plain_a_record():
    records = [
        {
            "type": "A",
            "name": "media",
            "fqdn": "media.home.geoffdavis.com.",
            "value": "172.29.50.20",
            "ttl": None,
            "status": "active",
            "managed": False,
        }
    ]
    result = netbox_dns_records_to_udm(records)
    assert result == [
        {
            "record_type": "A",
            "key": "media.home.geoffdavis.com",
            "value": "172.29.50.20",
            "enabled": True,
            "state": "present",
        }
    ]


def test_transform_cname_record_strips_trailing_dot_from_value():
    records = [
        {
            "type": "CNAME",
            "name": "syslog",
            "fqdn": "syslog.home.geoffdavis.com.",
            "value": "nas-sdg.iot.home.geoffdavis.com.",
            "ttl": None,
            "status": "active",
            "managed": False,
        }
    ]
    result = netbox_dns_records_to_udm(records)
    assert result == [
        {
            "record_type": "CNAME",
            "key": "syslog.home.geoffdavis.com",
            "value": "nas-sdg.iot.home.geoffdavis.com",
            "enabled": True,
            "state": "present",
        }
    ]


def test_transform_wildcard_record_uses_fqdn_directly():
    """Wildcards use the literal '*' in the relative name; `fqdn` already
    carries it through correctly server-side (*.nas.home.geoffdavis.com.)
    — this transform trusts that rather than re-deriving it from `name`
    + a zone-suffix string."""
    records = [
        {
            "type": "A",
            "name": "*.nas",
            "fqdn": "*.nas.home.geoffdavis.com.",
            "value": "100.92.233.103",
            "ttl": 3600,
            "status": "active",
            "managed": False,
        }
    ]
    result = netbox_dns_records_to_udm(records)
    assert result[0]["key"] == "*.nas.home.geoffdavis.com"
    assert result[0]["value"] == "100.92.233.103"


def test_transform_status_is_plain_string_not_nested_choice():
    """The exact bug netbox_import_udm_dns_records's reconcile_one.yml
    hit live: netbox-dns Record.status serializes as a plain string
    ("active"), unlike ipam.IPAddress.status's nested {value, label}
    shape. A record whose status is anything other than the literal
    string "active" (e.g. "inactive") must map to enabled=False without
    crashing on a `.value` attribute access that doesn't exist here."""
    records = [
        {
            "type": "A",
            "name": "old",
            "fqdn": "old.home.geoffdavis.com.",
            "value": "172.29.50.99",
            "ttl": None,
            "status": "inactive",
            "managed": False,
        }
    ]
    result = netbox_dns_records_to_udm(records)
    assert len(result) == 1
    assert result[0]["enabled"] is False


def test_transform_skips_managed_records():
    """managed=true marks netbox-dns's own auto-generated zone
    bookkeeping (SOA, apex NS) — these have no UDM static-DNS
    equivalent and must never be proposed as a create."""
    records = [
        {
            "type": "SOA",
            "name": "@",
            "fqdn": "home.geoffdavis.com.",
            "value": "unifi.home.geoffdavis.com. hostmaster.geoffdavis.com. 1 172800 7200 2419200 3600",
            "ttl": 3600,
            "status": "active",
            "managed": True,
        },
        {
            "type": "NS",
            "name": "@",
            "fqdn": "home.geoffdavis.com.",
            "value": "unifi.home.geoffdavis.com.",
            "ttl": None,
            "status": "active",
            "managed": True,
        },
        {
            "type": "A",
            "name": "media",
            "fqdn": "media.home.geoffdavis.com.",
            "value": "172.29.50.20",
            "ttl": None,
            "status": "active",
            "managed": False,
        },
    ]
    result = netbox_dns_records_to_udm(records)
    assert [r["key"] for r in result] == ["media.home.geoffdavis.com"]


def test_transform_apex_record_fqdn_has_no_leading_at():
    """The zone apex's relative `name` is the literal "@", but `fqdn`
    already resolves that to the real apex name server-side — this
    transform must use fqdn's value, not leak the "@" through."""
    records = [
        {
            "type": "A",
            "name": "@",
            "fqdn": "home.geoffdavis.com.",
            "value": "172.29.50.1",
            "ttl": None,
            "status": "active",
            "managed": False,
        }
    ]
    result = netbox_dns_records_to_udm(records)
    assert result[0]["key"] == "home.geoffdavis.com"
