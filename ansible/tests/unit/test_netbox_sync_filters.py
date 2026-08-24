"""Unit tests for filter_plugins/netbox_sync.py — the full symmetric-set
comparison, external-dns ownership exclusion, and NetBox->UDM record
transforms the design doc requires
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
    netbox_ip_to_reservation,
    normalize_mac,
    reservation_missing,
    reservation_ready,
)

# ── dns_external_dns_owned_keys ─────────────────────────────────────────


def test_owned_keys_finds_txt_heritage_marker():
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


def test_transform_apex_record():
    netbox_records = [{"name": "@", "type": "A", "value": "172.29.50.20", "status": "active"}]
    result = netbox_dns_records_to_udm(netbox_records, "home.geoffdavis.com")
    assert result == [
        {
            "record_type": "A",
            "key": "home.geoffdavis.com",
            "value": "172.29.50.20",
            "enabled": True,
            "state": "present",
        }
    ]


def test_transform_subdomain_record():
    netbox_records = [{"name": "syslog", "type": "CNAME", "value": "nas-sdg.iot.home.geoffdavis.com", "status": "active"}]
    result = netbox_dns_records_to_udm(netbox_records, "home.geoffdavis.com")
    assert result[0]["key"] == "syslog.home.geoffdavis.com"


def test_transform_inactive_status_is_disabled_not_dropped():
    netbox_records = [{"name": "old", "type": "A", "value": "172.29.50.99", "status": "inactive"}]
    result = netbox_dns_records_to_udm(netbox_records, "home.geoffdavis.com")
    assert len(result) == 1
    assert result[0]["enabled"] is False


# ── normalize_mac / netbox_ip_to_reservation / reservation_ready ───────


def test_normalize_mac_lowercases_valid_mac():
    assert normalize_mac("AA:BB:CC:DD:EE:FF") == "aa:bb:cc:dd:ee:ff"


def test_normalize_mac_rejects_malformed():
    assert normalize_mac("not-a-mac") is None
    assert normalize_mac("") is None
    assert normalize_mac(None) is None


def test_netbox_ip_to_reservation_extracts_bare_address():
    ip_obj = {
        "id": 42,
        "address": "172.29.10.31/24",
        "dns_name": "pacificbeach.home.geoffdavis.com",
        "assigned_object": {"mac_address": "AA:BB:CC:DD:EE:FF"},
    }
    reservation = netbox_ip_to_reservation(ip_obj)
    assert reservation == {
        "ip": "172.29.10.31",
        "mac": "aa:bb:cc:dd:ee:ff",
        "hostname": "pacificbeach.home.geoffdavis.com",
        "netbox_id": 42,
    }


def test_netbox_ip_to_reservation_missing_assigned_object_has_no_mac():
    ip_obj = {"id": 7, "address": "172.29.10.99/24", "dns_name": None, "assigned_object": None}
    reservation = netbox_ip_to_reservation(ip_obj)
    assert reservation["mac"] is None
    assert reservation_ready(reservation) is False


def test_reservation_ready_requires_both_ip_and_mac():
    assert reservation_ready({"ip": "172.29.10.31", "mac": "aa:bb:cc:dd:ee:ff"}) is True
    assert reservation_ready({"ip": None, "mac": "aa:bb:cc:dd:ee:ff"}) is False
    assert reservation_ready({"ip": "172.29.10.31", "mac": None}) is False


def test_reservation_missing_filters_correctly():
    reservations = [
        {"ip": "172.29.10.31", "mac": "aa:bb:cc:dd:ee:ff"},
        {"ip": "172.29.10.32", "mac": None},
        {"ip": None, "mac": "aa:bb:cc:dd:ee:00"},
    ]
    missing = reservation_missing(reservations)
    assert len(missing) == 2
    assert {"ip": "172.29.10.31", "mac": "aa:bb:cc:dd:ee:ff"} not in missing
