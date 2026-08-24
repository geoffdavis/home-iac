# unifi_network_ip_reservation

**New role** — pushes NetBox `status=dhcp` IP addresses to the UDM Pro /
UniFi Network controller's DHCP fixed-reservation list. Runs entirely
controller-side (`delegate_to: localhost`), same auth pattern as
[`unifi_network_dns_record`](../unifi_network_dns_record/README.md).

Added per [home-iac#8][issue] (tracking
[geoffdavis/ugreen-nas-compose#250][ugreen-250]) and
[`docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md`][spec].
Before this role, static IP assignment was **100% manual, UDM-UI-only**
— neither `unifi_network_dns_record` nor `unifi_network_dhcp_pxe`
touches per-host reservations. This is the role that closes the
pacificbeach-style gap: reconstructing VLAN 10's free DHCP range by hand
via several live UDM API calls, because nothing held the pool bounds or
in-use addresses as a queryable table.

[issue]: https://github.com/geoffdavis/home-iac/issues/8
[ugreen-250]: https://github.com/geoffdavis/ugreen-nas-compose/issues/250
[spec]: ../../../docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md

## Flow

1. Query NetBox for `status=dhcp` addresses whose containing prefix
   carries `unifi_network_ip_reservation_netbox_tag` ("tracked
   prefixes" in the spec).
2. Transform each into a draft `{ip, mac, hostname}` reservation. MAC
   comes from the address's assigned interface
   (`assigned_object.mac_address`) — an address with no assigned
   interface, or an interface with no MAC, is **logged loudly and
   dropped**, never guessed.
3. For each draft with both an IP and a MAC, resolve the VLAN of its
   containing NetBox prefix (`GET /api/ipam/prefixes/?contains=<ip>`,
   most-specific match) to a UDM `network_id` by matching VLAN name
   against the UDM's `networkconf` list. No match on either side →
   logged loudly, dropped, never pushed with a guessed network.
4. Authenticate to the UDM; reconcile each resolved reservation against
   the known-client list (`/rest/user`) by MAC — update on drift, create
   if the MAC has no client record yet.

## UDM endpoint — verification status

**This is the open question the spec calls out explicitly**
("Open questions: exact DHCP-reservation API shape on the UDM — verify
live, same as the pacificbeach pool-bounds check"). Two candidates were
considered:

- **UniFi Integration API**
  (`/proxy/network/integration/v1/sites/{siteId}/clients`) — this is a
  read-oriented client-listing endpoint; it does not document a
  fixed-IP/reservation write path. Not used.
- **Legacy v1 REST API** (`/proxy/network/api/s/<site>/rest/user`) —
  the well-established mechanism for UniFi fixed-IP reservations: a
  "known client" object with `use_fixedip` / `fixed_ip` / `network_id`
  fields, same v1 `{data: [...], meta: {rc: "ok"}}` envelope
  `unifi_network_port_forward` already uses against
  `/rest/portforward`. **This is what the role implements.**

This mirrors the same fallback pattern static-DNS needed this session
(the v2 API didn't cover static-DNS in some earlier attempt, so the
role fell back to a working endpoint) — but **unlike that case, this
endpoint choice has not been confirmed against a live controller**.
Specifically unverified:

- Whether `POST /rest/user` with a bare `{mac, use_fixedip, fixed_ip,
  network_id}` actually pre-provisions a reservation for a device the
  controller has never seen, or requires the client to already exist
  from prior DHCP/ARP discovery.
- The exact `PUT` semantics for updating an existing client's fixed-IP
  fields (full-object PUT vs. partial merge — this role sends the full
  desired sub-object, matching the other `unifi_network_*` roles'
  convention, but that convention was proven against `static-dns` and
  `portforward`, not `rest/user`).

Confirm both live once there's a safe test client to exercise them
against, before trusting this role's writes.

## No delete / un-reserve path

An address leaving NetBox's `status=dhcp` set is **not** currently
un-reserved on the UDM. This is a deliberate scope cut, not an
oversight: unlike DNS records (which carry no destructive risk beyond a
stale name), un-reserving a live device's IP could disrupt something
actually plugged in, and there's no marker distinguishing
role-managed reservations from ones set by hand in the UDM UI. Revisit
once there's a safe way to tag role-owned reservations (e.g. a `note`
field convention) and detect orphans without guessing.

## Credentials

- **UDM**: same 1Password item the other `unifi_network_*` roles use.
- **NetBox**: read-only token — safe to reuse the same 1Password item
  `unifi_network_dns_record` uses (both are read-only consumers). Never
  reuse `netbox_import_udm_state`'s write-scoped backfill token here.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `unifi_network_ip_reservation_enabled` | `false` | Opt-in gate |
| `unifi_network_ip_reservation_controller_url` | `https://172.29.50.1` | UDM base URL |
| `unifi_network_ip_reservation_validate_certs` | `false` | UDM ships self-signed |
| `unifi_network_ip_reservation_site` | `default` | UniFi site identifier |
| `unifi_network_ip_reservation_creds_op_item` / `_op_vault` | UDM item/vault | 1P UDM creds |
| `unifi_network_ip_reservation_netbox_url` | `https://netbox.home.geoffdavis.com` | NetBox base URL |
| `unifi_network_ip_reservation_netbox_creds_op_item` / `_op_vault` | NetBox read-only token item/vault | 1P NetBox creds |
| `unifi_network_ip_reservation_netbox_tag` | `unifi-managed` | NetBox prefix tag marking "tracked" prefixes |
| `unifi_network_ip_reservation_netbox_page_limit` / `_max_pages` | `200` / `20` | Pagination bounds |

## Known gaps

- **Live NetBox testing is pending [nix-personal#542][np542].** Written
  against NetBox's documented `/api/ipam/ip-addresses/` and
  `/api/ipam/prefixes/?contains=` contract; never queried a running
  instance.
- **The UDM reservation endpoint is unverified** — see above.
- **No orphan/un-reserve detection** — see above.
- **`nas-cin` is currently offline** (fleet outage, ongoing as of this
  PR). This role has no hardcoded per-site data, so nothing here blocks
  on it — but any live verification pass, or a future backfill of
  nas-cin's existing static reservations into NetBox, needs to skip it
  rather than treat it as reachable.

[np542]: https://github.com/geoffdavis/nix-personal/issues/542

## Failure modes

- **NetBox address missing an assigned interface, or the interface has
  no MAC**: logged, dropped, never guessed.
- **No VLAN on the containing prefix, or no UDM network with that
  name**: logged, dropped, never pushed with a guessed `network_id`.
- **POST/PUT response `meta.rc != "ok"`**: loud assertion failure with
  the raw response.
- **CSRF token missing**: same diagnosis path as the other
  `unifi_network_*` roles.
