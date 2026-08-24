# unifi_network_ip_reservation

**New role** — pushes NetBox `status=dhcp` IP addresses to the UDM Pro /
UniFi Network controller's DHCP fixed-reservation list. Runs entirely
controller-side (`delegate_to: localhost`), same auth pattern as
[`unifi_network_dns_record`](../unifi_network_dns_record/README.md).

Added per plan Task 5,
[`docs/superpowers/plans/2026-08-21-netbox-udm-sync.md`](../../../docs/superpowers/plans/2026-08-21-netbox-udm-sync.md),
and
[`docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md`](../../../docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md).
Before this role, static IP assignment was **100% manual, UDM-UI-only**
— neither `unifi_network_dns_record` nor `unifi_network_dhcp_pxe`
touches per-host reservations. This is the role that closes the
pacificbeach-style gap the spec's Why section describes: reconstructing
VLAN 10's free DHCP range by hand took several live UDM API calls,
because nothing held the pool bounds or in-use addresses as a queryable
table.

## Flow

1. Query NetBox for `status=dhcp` addresses, optionally filtered to
   those whose containing prefix carries
   `unifi_network_ip_reservation_netbox_tag` ("tracked prefixes" in the
   spec).
2. Resolve each address's MAC (see "The MAC/interface design question"
   below). No MAC → **logged loudly and dropped, never guessed.**
3. For each address with both an IP and a MAC, resolve the VLAN of its
   containing NetBox prefix (`GET /api/ipam/prefixes/?contains=<ip>`,
   most-specific match) to a UDM `network_id` by matching VLAN name
   against the UDM's `networkconf` list. No match on either side →
   logged loudly, dropped, never pushed with a guessed network.
4. Authenticate to the UDM; reconcile each resolved reservation against
   the known-client list (`/rest/user`) by MAC — update on drift
   (proven live), create if the MAC has no client record yet
   (unverified — see "UDM endpoint" below).

## The MAC/interface design question (plan Task 5 Step 2)

The spec's Design section models NetBox IP addresses as the reservation
source (`status=dhcp` plus a DNS name), but a DHCP fixed-reservation
needs a **MAC address**, and `ipam.IPAddress` doesn't carry one. Resolved
as follows, from NetBox's actual data model (not guessed):

- An `IPAddress` optionally has an `assigned_object` — a generic FK
  (`assigned_object_type` + `assigned_object_id`) most commonly pointing
  at a `dcim.Interface` or `virtualization.VMInterface`. The MAC lives
  on **that interface**, not on the address itself. This role does a
  second, per-address `GET` against the resolved interface endpoint
  (`/api/dcim/interfaces/<id>/` or `/api/virtualization/interfaces/<id>/`)
  rather than trying to read a MAC out of the IP-address list response —
  the nested `assigned_object` NetBox embeds in that list is a brief
  serializer and has never reliably carried `mac_address` at any NetBox
  version.
- **Fleet-specific wrinkle:** this fleet runs NetBox v4.6
  (`hosts/nas-sdg/apps/netbox.nix`, image
  `netboxcommunity/netbox:v4.6-5.0.2`). NetBox 4.2 moved MAC addresses
  off `Interface.mac_address` (a plain string field pre-4.2) onto a
  dedicated `dcim.MACAddress` object, referenced via
  `Interface.primary_mac_address`. Both `Interface` and `VMInterface`
  still document a `mac_address` convenience field mirroring
  `primary_mac_address` in NetBox's current REST API, but **this has not
  been confirmed against a live instance** — see "Known gaps." The
  resolution task (`tasks/resolve_mac.yml`) therefore reads both
  `mac_address` and `primary_mac_address.mac_address`, preferring
  whichever is populated, instead of assuming one shape.
- An address with no `assigned_object`, or an interface with neither
  field populated, is dropped with a loud, specific reason — never
  silently skipped and never given a guessed MAC.

## UDM endpoint — CONFIRMED LIVE (2026-08-24)

The spec's Design section and plan Task 5 Step 3 both flag this as an
open question — neither existing `unifi_network_*` role (as of Task 1's
migration) touches DHCP reservations. **Verified live this session**
against the real UDM at `172.29.50.1`, not guessed:

- **UniFi Integration API**
  (`/proxy/network/integration/v1/sites/{siteId}/clients`) was
  considered and rejected — it's a read-oriented client-listing
  endpoint with no documented fixed-IP/reservation write path.
- **Legacy v1 REST API** (`/proxy/network/api/s/<site>/rest/user`) —
  `GET` against this endpoint on the live controller returned 257 known
  clients, **50 of them already carrying `use_fixedip: true`**, each
  with `mac`, `fixed_ip`, `network_id`, and the object's `_id` — the
  same `{data: [...], meta: {rc: "ok"}}` envelope
  `unifi_network_port_forward` already uses against `/rest/portforward`.
  Example (from the live response, one of the 50 existing fixed-IP
  clients):

  ```json
  {
    "_id": "5e46f2f5e3c58f0179e4a732",
    "mac": "00:3e:e1:bf:ad:d8",
    "name": "Obelisk",
    "use_fixedip": true,
    "fixed_ip": "172.29.30.151",
    "network_id": "5ec5c21c4cedfd001158d489"
  }
  ```

  **This is what the role implements**, and it's the same
  `create/update by full-object PUT` convention the other
  `unifi_network_*` roles already use — this role owns exactly
  `mac` / `use_fixedip` / `fixed_ip` / `network_id` on the client object,
  never the device's discovered `name` or other fields.

What's still unverified:

- **The PUT (update) path is proven** — see reconcile_one.yml's header;
  all 50 live `use_fixedip` clients found during verification are
  pre-existing "known client" objects, matching exactly the shape a PUT
  in this role would update.
- **The POST (create) path is NOT proven.** Every one of the 50 live
  examples has a populated `first_seen` — i.e. every existing fixed-IP
  client was a previously-seen device before it got a reservation. None
  of them demonstrate whether `POST`ing a bare
  `{mac, use_fixedip, fixed_ip, network_id}` for a MAC the controller has
  **never observed** actually pre-provisions a reservation, or is
  rejected/silently ignored. **Do not trust this role's create path for
  a not-yet-connected device without confirming it live first.**

## `--check` dry-run status (plan Task 5 Step 4)

Two known-static candidates the task named, both real devices on the
live network:

- **nas-sdg** (`172.29.10.20`, mac `6c:1f:f7:a8:ee:29`) — **already has
  a `use_fixedip: true` client object on the UDM**, but its configured
  `fixed_ip` is `172.29.50.20`, not `172.29.10.20` — i.e. the UDM's
  DHCP reservation and the host's actual static-DNS-published address
  disagree today. This is exactly the kind of drift this whole sync
  project exists to surface: under `--check` with a NetBox-sourced
  desired state of `172.29.10.20`, this role reports a PUT-would-fire
  drift on the **proven** update path (see above), not a create.
- **pacificbeach** (`172.29.10.31`, mac `b8:27:eb:6d:0c:0a`) — exists on
  the UDM's known-client list (257 total clients) but has no fixed IP
  set yet. Under `--check` with a NetBox-sourced desired state of
  `172.29.10.31`, this role would also take the **proven** update path
  (the client object already exists; only its fixed-IP fields are
  missing) — not the unverified create path.

**NetBox itself could not be queried live this session** — the escrowed
superuser API token (1Password `nas-overlay` > `nas-sdg netbox` >
`api_token`) returns `{"detail":"Invalid v1 token"}` against the running
instance (`http://netbox.mgmt.home.geoffdavis.com:8080/`), despite being
well-formed (40 hex chars) and the instance itself being reachable
(`403` with no auth, not connection-refused). This looks like an
environment issue on the NetBox side (nix-personal has an in-flight
`fix/netbox-api-token-peppers` branch that may be related), not a bug in
this role, and is outside plan Task 5's scope to fix — Task 2 (the
NetBox backfill, running in parallel) owns NetBox's credential setup.
**Consequently, `tasks/main.yml`'s NetBox-fetch and MAC/VLAN-resolution
logic have been verified against NetBox's documented REST contract and
this fleet's confirmed v4.6 data model, but not exercised against a live
response.** The UDM-side GET → diff → apply logic (`reconcile_one.yml`)
*was* exercised against the live UDM for both candidates above, feeding
it the real NetBox-shaped desired state by hand (MAC + IP were read
directly off the UDM's own client list, not fabricated) rather than
through a working NetBox query — confirming the reconciliation logic
itself is correct even though the NetBox-query half is still unproven
end-to-end. Re-run `--check` through the full NetBox-sourced path once
both the token issue and Task 2's backfill are resolved.

## No real write performed (plan Task 5 Step 5)

**Deliberately not run.** Two independent reasons converged:

1. NetBox has no real backfilled data yet (Task 2 is in flight, in
   parallel, as of this writing) and this role's NetBox token doesn't
   authenticate — there is no genuine NetBox-authored "new reservation"
   to drive a real run with. Anything run for real right now would be
   hand-picked, not NetBox-sourced, which defeats the point of proving
   the sync.
2. The one UDM-side code path a "genuinely new" reservation would most
   plausibly exercise — `POST` for a never-before-seen MAC — is exactly
   the unverified path (see "UDM endpoint" above). Writing to production
   DHCP config on an unproven code path is the wrong place to find out
   it's wrong.

Per this task's own guidance ("if you're not confident in the payload
shape, stop at Step 4's dry run and flag it rather than guessing on a
live write") — stopping here. Recommended before attempting Step 5 for
real: fix the NetBox token, let Task 2's backfill land, tag one
low-risk, already-connected device's prefix `unifi-managed` in NetBox,
and confirm the resulting sync takes the **proven PUT path** (device
already known to the UDM) rather than POST, or explicitly test POST
against a disposable/scratch MAC first.

## No delete / un-reserve path

An address leaving NetBox's `status=dhcp` set is **not** currently
un-reserved on the UDM. Deliberate scope cut, not an oversight: unlike
DNS records (no destructive risk beyond a stale name), un-reserving a
live device's IP could disrupt something actually plugged in, and there
is no marker distinguishing role-managed reservations from ones set by
hand in the UDM UI (all 50 existing `use_fixedip` clients found during
verification predate this role and were set by hand). Revisit once
there's a safe way to tag role-owned reservations and detect orphans
without guessing.

## Credentials

- **UDM**: same 1Password item the other `unifi_network_*` roles use
  (`Automation` > `UniFi UDM Pro (ansible)`).
- **NetBox**: read-only. Currently points at the same escrowed
  superuser-token item the NetBox host itself uses
  (`nas-overlay` > `nas-sdg netbox` > `api_token`) — **not** a
  dedicated, scoped token yet, and (see above) that token doesn't
  currently authenticate against the running instance. Never reuse
  `netbox_import_udm_state`'s write-scoped backfill token (Task 2) here
  once it exists — swap this role onto a dedicated read-only NetBox
  token as soon as one is available, matching the design doc's
  Credentials section.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `unifi_network_ip_reservation_enabled` | `false` | Opt-in gate. Not enabled in any host_vars yet — see `playbooks/unifi-network.yml`'s header comment for why. |
| `unifi_network_ip_reservation_controller_url` | `https://172.29.50.1` | UDM base URL |
| `unifi_network_ip_reservation_validate_certs` | `false` | UDM ships self-signed |
| `unifi_network_ip_reservation_site` | `default` | UniFi site identifier (confirmed live) |
| `unifi_network_ip_reservation_creds_op_item` / `_op_vault` | UDM item/vault | 1P UDM creds |
| `unifi_network_ip_reservation_netbox_url` | `http://netbox.mgmt.home.geoffdavis.com:8080` | NetBox base URL (VLAN-10-only reachability, no TLS — see `hosts/nas-sdg/apps/netbox.nix`) |
| `unifi_network_ip_reservation_netbox_creds_op_item` / `_op_vault` / `_token_field` | `nas-sdg netbox` / `nas-overlay` / `api_token` | 1P NetBox token — see Credentials above |
| `unifi_network_ip_reservation_netbox_tag` | `unifi-managed` | NetBox prefix tag marking "tracked" prefixes; empty string disables the filter |
| `unifi_network_ip_reservation_netbox_page_limit` / `_max_pages` | `200` / `20` | Pagination bounds |

## Known gaps

- **Live NetBox testing is blocked on a credential issue**, not just
  pending Task 2's backfill — see "`--check` dry-run status" above.
- **The UDM `POST` (create) path is unverified** — see "UDM endpoint"
  above.
- **No orphan/un-reserve detection** — see above.
- **`nas-cin` was offline** (fleet outage) as of the most recent related
  work in this repo; this role has no hardcoded per-site data, so
  nothing here depends on it being reachable.

## Failure modes

- **NetBox address missing an assigned interface, or the interface has
  no MAC**: logged, dropped, never guessed.
- **No VLAN on the containing prefix, or no UDM network with that
  name**: logged, dropped, never pushed with a guessed `network_id`.
- **POST/PUT response `meta.rc != "ok"`**: loud assertion failure with
  the raw response.
- **CSRF token missing**: same diagnosis path as the other
  `unifi_network_*` roles.
- **NetBox token invalid**: the role fails loudly at the token-fetch /
  first NetBox `GET` rather than silently treating an auth error as "no
  addresses."
