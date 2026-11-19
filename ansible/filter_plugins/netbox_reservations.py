"""Filter plugins backing the one-shot UDM -> NetBox reservation backfill
(roles/netbox_import_udm_reservations).

The ongoing sync runs the other way (NetBox -> UDM,
roles/unifi_network_ip_reservation). It reads NetBox `status=dhcp` IP
addresses tagged `unifi-managed`, and takes each one's MAC from the
interface the address is assigned to. Before it can be turned on, NetBox
has to describe every reservation the UDM already holds, or the first
real sync would have nothing to compare against. This module plans that
backfill: it compares the UDM's fixed-IP clients with NetBox's current
objects and returns the list of writes that make NetBox match, plus
anything it refuses to guess about.

Plain Python, so tests/unit/test_netbox_reservations.py can exercise it
without Ansible. The role only executes the plan.

Never deletes and never reassigns: an address or MAC that NetBox already
ties to something else is reported as a conflict for a human, not
"fixed".
"""

from __future__ import annotations

import ipaddress

MANAGED_TAG = "unifi-managed"


def _ip_only(address):
    return address.split("/", 1)[0]


def _norm_mac(mac):
    return (mac or "").strip().lower()


def _containing_prefix(ip, prefixes):
    """Most-specific NetBox prefix containing `ip`, or None."""
    addr = ipaddress.ip_address(ip)
    best = None
    for p in prefixes:
        net = ipaddress.ip_network(p["prefix"], strict=False)
        if addr in net and (best is None or net.prefixlen > best[0].prefixlen):
            best = (net, p)
    return best


def _client_name(client):
    name = (client.get("name") or client.get("hostname") or "").strip()
    return name or "udm-" + _norm_mac(client["mac"]).replace(":", "")


def _tag_slugs(obj):
    return [t["slug"] for t in obj.get("tags") or []]


def _with_managed_tag(obj):
    slugs = _tag_slugs(obj)
    if MANAGED_TAG not in slugs:
        slugs.append(MANAGED_TAG)
    return [{"slug": s} for s in slugs]


def udm_reservation_backfill_plan(udm_clients, nb_ips, nb_macs, nb_devices, nb_prefixes):
    """Return {"actions": [...], "conflicts": [...], "in_sync": [...]}.

    Each action has a `kind`:
      - patch_ip: an existing NetBox address needs status/tag/assignment
        changes (`ip_id`, `body`).
      - create_ip: no NetBox address yet, but NetBox already has an
        interface with this MAC (`body` assigns the new address to it).
      - create_device: neither the address nor the MAC is in NetBox.
        The role creates a device, an interface, a MAC object (set as the
        interface's primary MAC), then creates or patches the address
        (`device_name`, `mac`, `address`, `existing_ip_id`, `ip_body`).
    """
    ips = {_ip_only(a["address"]): a for a in nb_ips}
    macs = {_norm_mac(m["mac_address"]): m for m in nb_macs}
    device_names = {d["name"] for d in nb_devices if d.get("name")}

    actions, conflicts, in_sync = [], [], []
    planned_names = set()

    reservations = [c for c in udm_clients if c.get("use_fixedip") and c.get("fixed_ip")]
    for c in sorted(reservations, key=lambda c: tuple(int(o) for o in c["fixed_ip"].split("."))):
        ip, mac, name = c["fixed_ip"], _norm_mac(c["mac"]), _client_name(c)
        ref = {"ip": ip, "mac": mac, "name": name}

        pfx = _containing_prefix(ip, nb_prefixes)
        if pfx is None:
            conflicts.append({**ref, "reason": "no NetBox prefix contains this address"})
            continue
        address = f"{ip}/{pfx[0].prefixlen}"

        nb_ip = ips.get(ip)
        nb_mac = macs.get(mac)
        mac_iface = None
        if nb_mac and nb_mac.get("assigned_object_type") and nb_mac.get("assigned_object_id"):
            mac_iface = (nb_mac["assigned_object_type"], nb_mac["assigned_object_id"])

        if nb_ip is not None:
            assigned = None
            if nb_ip.get("assigned_object_type") and nb_ip.get("assigned_object_id"):
                assigned = (nb_ip["assigned_object_type"], nb_ip["assigned_object_id"])

            body = {}
            if nb_ip["status"]["value"] != "dhcp":
                body["status"] = "dhcp"
            if MANAGED_TAG not in _tag_slugs(nb_ip):
                body["tags"] = _with_managed_tag(nb_ip)

            if assigned is None:
                if mac_iface is not None:
                    body["assigned_object_type"], body["assigned_object_id"] = mac_iface
                elif nb_mac is not None:
                    conflicts.append({**ref, "reason": "MAC is in NetBox but not assigned to any interface"})
                    continue
                else:
                    if name in device_names or name in planned_names:
                        conflicts.append({**ref, "reason": f"device '{name}' already exists without this MAC"})
                        continue
                    planned_names.add(name)
                    actions.append({**ref, "kind": "create_device", "device_name": name,
                                    "address": address, "existing_ip_id": nb_ip["id"], "ip_body": body})
                    continue
            elif mac_iface is None or mac_iface != assigned:
                conflicts.append({**ref, "reason": (
                    "address is assigned to an interface that does not carry this MAC in NetBox"
                    if mac_iface is None else
                    "address and MAC are on different NetBox interfaces")})
                continue

            if body:
                actions.append({**ref, "kind": "patch_ip", "ip_id": nb_ip["id"], "body": body})
            else:
                in_sync.append(ref)
            continue

        new_body = {"address": address, "status": "dhcp", "tags": [{"slug": MANAGED_TAG}],
                    "description": f"UniFi DHCP reservation for {name} (backfilled)"}
        if mac_iface is not None:
            new_body["assigned_object_type"], new_body["assigned_object_id"] = mac_iface
            actions.append({**ref, "kind": "create_ip", "body": new_body})
        elif nb_mac is not None:
            conflicts.append({**ref, "reason": "MAC is in NetBox but not assigned to any interface"})
        elif name in device_names or name in planned_names:
            conflicts.append({**ref, "reason": f"device '{name}' already exists without this MAC"})
        else:
            planned_names.add(name)
            actions.append({**ref, "kind": "create_device", "device_name": name,
                            "address": address, "existing_ip_id": None, "ip_body": new_body})

    return {"actions": actions, "conflicts": conflicts, "in_sync": in_sync}


def udm_dhcp_range_plan(udm_networks, nb_prefixes, nb_ranges):
    """IP ranges to create so NetBox shows each UDM DHCP pool.

    Only networks with DHCP on and a containing NetBox prefix; a range
    already starting at the pool's first address counts as present (its
    end is not rewritten here).
    """
    existing_starts = {_ip_only(r["start_address"]) for r in nb_ranges}
    out = []
    for n in udm_networks:
        start, stop = n.get("dhcpd_start"), n.get("dhcpd_stop")
        if not (n.get("dhcpd_enabled") and start and stop):
            continue
        pfx = _containing_prefix(start, nb_prefixes)
        if pfx is None or start in existing_starts:
            continue
        plen = pfx[0].prefixlen
        out.append({"network": n.get("name"), "body": {
            "start_address": f"{start}/{plen}", "end_address": f"{stop}/{plen}",
            "status": "active", "mark_populated": False,
            "description": f"UniFi DHCP pool ({n.get('name')})",
            "tags": [{"slug": MANAGED_TAG}]}})
    return out


class FilterModule:
    def filters(self):
        return {
            "udm_reservation_backfill_plan": udm_reservation_backfill_plan,
            "udm_dhcp_range_plan": udm_dhcp_range_plan,
        }
