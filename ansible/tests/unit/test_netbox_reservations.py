"""Unit tests for filter_plugins/netbox_reservations.py, the planner for
the one-shot UDM -> NetBox reservation backfill."""

from filter_plugins.netbox_reservations import (
    MANAGED_TAG,
    udm_dhcp_range_plan,
    udm_reservation_backfill_plan,
)

PREFIXES = [{"prefix": "172.29.60.0/24"}, {"prefix": "172.29.0.0/16"}]
IFACE = ("dcim.interface", 7)


def client(ip, mac, name="thing", fixed=True):
    return {"fixed_ip": ip, "mac": mac, "name": name, "use_fixedip": fixed}


def nb_ip(ip, status="active", assigned=None, tags=(), id_=1):
    obj = {"id": id_, "address": f"{ip}/24", "status": {"value": status}, "tags": [{"slug": t} for t in tags]}
    if assigned:
        obj["assigned_object_type"], obj["assigned_object_id"] = assigned
    return obj


def nb_mac(mac, assigned=IFACE):
    obj = {"mac_address": mac.upper()}
    if assigned:
        obj["assigned_object_type"], obj["assigned_object_id"] = assigned
    return obj


def plan(clients, ips=(), macs=(), devices=()):
    return udm_reservation_backfill_plan(list(clients), list(ips), list(macs), list(devices), PREFIXES)


def test_non_fixed_clients_are_ignored():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01", fixed=False)])
    assert p == {"actions": [], "conflicts": [], "in_sync": []}


def test_fully_matching_address_is_in_sync():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01")],
             ips=[nb_ip("172.29.60.40", "dhcp", IFACE, [MANAGED_TAG])],
             macs=[nb_mac("aa:bb:cc:00:00:01")])
    assert p["actions"] == [] and p["conflicts"] == []
    assert p["in_sync"][0]["ip"] == "172.29.60.40"


def test_existing_address_gets_status_and_tag_without_dropping_tags():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01")],
             ips=[nb_ip("172.29.60.40", "active", IFACE, ["nas_nixos"], id_=9)],
             macs=[nb_mac("aa:bb:cc:00:00:01")])
    (a,) = p["actions"]
    assert a["kind"] == "patch_ip" and a["ip_id"] == 9
    assert a["body"]["status"] == "dhcp"
    assert a["body"]["tags"] == [{"slug": "nas_nixos"}, {"slug": MANAGED_TAG}]


def test_unassigned_address_is_attached_to_the_mac_interface():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01")],
             ips=[nb_ip("172.29.60.40")], macs=[nb_mac("aa:bb:cc:00:00:01")])
    (a,) = p["actions"]
    assert a["body"]["assigned_object_type"] == "dcim.interface"
    assert a["body"]["assigned_object_id"] == 7


def test_unassigned_address_with_unknown_mac_creates_a_device():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01", "hassio")], ips=[nb_ip("172.29.60.40", id_=4)])
    (a,) = p["actions"]
    assert a["kind"] == "create_device" and a["existing_ip_id"] == 4
    assert a["device_name"] == "hassio" and a["address"] == "172.29.60.40/24"


def test_missing_address_on_known_mac_creates_ip_on_that_interface():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01")], macs=[nb_mac("aa:bb:cc:00:00:01")])
    (a,) = p["actions"]
    assert a["kind"] == "create_ip"
    assert a["body"]["address"] == "172.29.60.40/24"  # most specific prefix wins
    assert a["body"]["status"] == "dhcp"
    assert a["body"]["assigned_object_id"] == 7


def test_missing_address_and_mac_creates_a_device():
    p = plan([client("172.29.60.41", "aa:bb:cc:00:00:02", "  dryer ")])
    (a,) = p["actions"]
    assert a["kind"] == "create_device" and a["device_name"] == "dryer"
    assert a["existing_ip_id"] is None and a["ip_body"]["tags"] == [{"slug": MANAGED_TAG}]


def test_nameless_client_gets_a_mac_based_name():
    p = plan([{"fixed_ip": "172.29.60.41", "mac": "AA:BB:CC:00:00:02", "use_fixedip": True}])
    assert p["actions"][0]["device_name"] == "udm-aabbcc000002"


def test_address_on_another_interface_is_a_conflict_not_a_move():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01")],
             ips=[nb_ip("172.29.60.40", assigned=("dcim.interface", 99))],
             macs=[nb_mac("aa:bb:cc:00:00:01")])
    assert p["actions"] == []
    assert "different NetBox interfaces" in p["conflicts"][0]["reason"]


def test_existing_device_name_without_the_mac_is_a_conflict():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01", "voronica")], devices=[{"name": "voronica"}])
    assert p["actions"] == [] and "already exists" in p["conflicts"][0]["reason"]


def test_two_clients_with_one_name_create_only_one_device():
    p = plan([client("172.29.60.40", "aa:bb:cc:00:00:01", "x"), client("172.29.60.41", "aa:bb:cc:00:00:02", "x")])
    assert [a["kind"] for a in p["actions"]] == ["create_device"]
    assert len(p["conflicts"]) == 1


def test_address_outside_every_prefix_is_a_conflict():
    p = plan([client("10.9.9.9", "aa:bb:cc:00:00:01")])
    assert p["conflicts"][0]["reason"] == "no NetBox prefix contains this address"


def test_dhcp_range_plan_skips_disabled_and_existing_pools():
    nets = [
        {"name": "NoT", "dhcpd_enabled": True, "dhcpd_start": "172.29.60.100", "dhcpd_stop": "172.29.60.200"},
        {"name": "Off", "dhcpd_enabled": False, "dhcpd_start": "172.29.61.100", "dhcpd_stop": "172.29.61.200"},
        {"name": "Has", "dhcpd_enabled": True, "dhcpd_start": "172.29.62.100", "dhcpd_stop": "172.29.62.200"},
    ]
    out = udm_dhcp_range_plan(nets, PREFIXES, [{"start_address": "172.29.62.100/16"}])
    assert [o["network"] for o in out] == ["NoT"]
    assert out[0]["body"]["start_address"] == "172.29.60.100/24"
    assert out[0]["body"]["end_address"] == "172.29.60.200/24"
