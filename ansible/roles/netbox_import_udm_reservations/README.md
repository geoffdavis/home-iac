# netbox_import_udm_reservations

One-shot, re-runnable **UDM -> NetBox** backfill of DHCP reservations and
DHCP pools. It exists so the ongoing **NetBox -> UDM** sync
([`unifi_network_ip_reservation`](../unifi_network_ip_reservation/README.md))
starts from a NetBox that already matches the UDM.

```sh
uv run --group dev ansible-playbook playbooks/netbox-import.yml --tags reservations --check   # plan only
uv run --group dev ansible-playbook playbooks/netbox-import.yml --tags reservations           # apply
```

## What it does

For every UDM known client with `use_fixedip: true`:

| NetBox state | Action |
| --- | --- |
| Address exists, on the interface that carries the client's MAC | set `status=dhcp`, add tag `unifi-managed` (other tags kept) |
| Address exists, unassigned, MAC known | attach it to the MAC's interface, same status/tag |
| Address missing, MAC known | create the address on that interface |
| Neither known | create a device (role *UniFi Client*, type *Unclassified network client*), interface `nic0`, the MAC (as the interface's primary MAC) and the address |
| Address on another interface, MAC on another interface, device name taken, no containing prefix | **conflict**: printed, left alone |

It also creates a NetBox IP range for every UDM network's DHCP pool, unless
a range already starts at the pool's first address.

The planning is plain Python
([`filter_plugins/netbox_reservations.py`](../../filter_plugins/netbox_reservations.py),
tested in `tests/unit/test_netbox_reservations.py`); the tasks only execute
the plan. It never deletes or reassigns anything. Under `--check` it prints
the plan and writes nothing.

## Credentials

- NetBox: the `ansible` service account's write-enabled token
  (`nas-overlay` / `netbox-ansible-service-account` / `credential`). Its
  ObjectPermission `ansible-ipam-reservation-sync` allows view/add/change
  (no delete) on addresses, ranges, prefixes, VLANs, devices, interfaces,
  MACs, device types, manufacturers, device roles, sites and tags.
- UDM: `UniFi UDM Pro (ansible)` from the `Automation` vault.

Not the local NetBox `admin` account: it is deliberately inactive (see
nix-personal `hosts/nas-sdg/apps/netbox.nix`), so its tokens answer
"User inactive".

## History

Run live 2026-11-18: 56 reservations (21 addresses updated, 1 created on a
known interface, 34 placeholder devices created) and 10 DHCP-pool ranges.
A second `--check` run planned nothing. Placeholder devices are named after
the UDM client; reclassify them in NetBox freely, the sync only reads the
interface MAC and the address.
