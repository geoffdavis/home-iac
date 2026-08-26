# netbox_import_udm_state

**One-shot** backfill of NetBox's `ipam.IPAddress` objects from the UDM's
current static-DNS list plus the documented VLAN 10 "low address" list.
This is plan Task 2 / Gate G2 of
[`docs/superpowers/plans/2026-08-21-netbox-udm-sync.md`](../../../docs/superpowers/plans/2026-08-21-netbox-udm-sync.md).
See also
[the design spec](../../../docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md),
"Phase 1 import" and "Data model in NetBox".

Idempotent (GET -> diff -> create/update, same shape as
[`unifi_network_dns_record`](../unifi_network_dns_record/README.md)) but
meant to run once -- or be re-run by hand if UDM state drifts before Task
3's ongoing sync exists. **Never deletes anything from NetBox.**

## DNS-plugin decision (resolved)

Checked live against the running instance 2026-08-24
(`GET /api/status/`): **`"plugins":{}` -- no plugins installed, including
`netbox-dns`.** This role therefore uses the spec's stated fallback:
`ipam.IPAddress`'s built-in `dns_name` field. **A/AAAA records only** --
the UDM's `CNAME`, `NS`, `MX` and `TXT` static-DNS records have no home in
this data model and are silently skipped (not represented in NetBox at
all, not an error).

## Before running this role: create the write-scoped token

**This role needs a NetBox API token that does not exist yet.** Per the
design doc's Credentials section, it must be its **own** 1Password item --
separate from both the NetBox superuser bootstrap token (`nas-sdg netbox`
in the same vault, used only for `nix-personal`'s own provisioning of the
NetBox container) and the read-only token Task 3's ongoing sync will use
later.

1. In the NetBox UI (`http://netbox.mgmt.home.geoffdavis.com:8080`, or
   `http://172.29.10.20:8080` with a `Host: netbox.mgmt.home.geoffdavis.com`
   header), log in as `admin` and go to your user menu -> **API Tokens**
   -> **Add a token**.
   - **Write enabled: yes.** NetBox 4.6+ tokens carry a `write_enabled`
     flag independent of the underlying user's own permissions -- this is
     what makes the token "write-scoped" versus Task 3's future
     `write_enabled: false` token, without needing a second user account.
   - Description: something identifying this as the Task 2 one-shot
     backfill token.
   - Leave no expiration, or set one and note it -- this token only needs
     to exist for as long as backfills (initial + any re-runs) happen.
2. NetBox 4.6+ issues v2 tokens as the composed `nbt_<key>.<token>`
   string -- copy the **full token value shown at creation time** (it is
   only ever shown once). Do **not** copy the masked ~12-char `key`/
   `display` value shown later in the token list.
3. Store it in 1Password, vault `nas-overlay`, as its own item:
   - Item name: `netbox-udm-import-token` (matches
     `netbox_import_udm_state_netbox_token_op_item` in `defaults/main.yml`
     -- change both together if you use a different name).
   - Field: `token` (concealed), value = the full `nbt_...` string from
     step 2.
4. Use it as `Authorization: Bearer <token>` -- **not** `Authorization:
   Token <token>` (that's the old v1 header format; v4.6+ tokens are
   already the composed string, don't prefix with `Token ` either).

This role's `defaults/main.yml` already points at that 1Password location;
once the item exists, nothing else needs configuring.

## What it imports

1. **The UDM's live static-DNS list** (`GET
   /proxy/network/v2/api/site/default/static-dns`, same auth/endpoint
   `unifi_network_dns_record` already uses), filtered to `A`/`AAAA`
   records.
2. **Minus** any record whose key matches an `external-dns` ownership TXT
   marker (`_externaldns.a-<name>` -> `...heritage=external-dns...`) --
   those are Kubernetes/Cilium-owned, not static desired state. Confirmed
   live 2026-08-24: this excludes `website-dev.k8s`, `website-prod.k8s`
   and `hubble.k8s` (all point at `172.29.55.0`, the Cilium LB pool's
   network address, not a real host).
3. **Grouped by target address** -- several DNS names commonly share one
   IP (the nas-sdg/netbox mgmt aliases at `.20`, the `*.admin`/`*.nas`
   split-horizon wildcards at the netbird overlay address, etc.).
   `ipam.IPAddress` has exactly one `dns_name` field, so one name per
   group is picked as the object's `dns_name`; the rest are recorded as
   an "aliases (not represented...)" note in the object's `description` --
   not silently dropped, just not independently queryable the way a real
   DNS-record plugin would let them be.
4. **Plus** the documented VLAN 10 "low address" list from
   `defaults/main.yml` (`netbox_import_udm_state_low_addresses`), for
   addresses that have no static-DNS record at all (gateway, JetKVMs,
   Talos secondary NICs, torrey, rpi4-mgmt) -- de-duplicated against
   anything already covered by step 3. Each entry's `status` (`dhcp` vs.
   `active`) was cross-checked live 2026-08-24 against the UDM's
   `stat/sta` active-client list (`use_fixedip` true -> `dhcp`, matching
   the design doc's convention of using NetBox's `dhcp` status for a
   pinned DHCP reservation; no fixed-ip entry -> `active`, a plain static
   host-side config, same as pacificbeach).

## What it does NOT do

- Does not create `ipam.Prefix`/VLAN objects. The design doc's Data model
  section describes one NetBox Prefix per UDM VLAN "imported in Phase 1",
  but `nix-personal`'s actual Phase 1
  (`hosts/nas-sdg/apps/netbox.nix`) explicitly scoped that out ("No
  backfill from the UDM API... that is a data-import task tracked in the
  Phase 2 spec/plan pair") -- and NetBox currently has zero Prefixes
  (confirmed live 2026-08-24). This role's IP-address objects therefore
  exist without a parent Prefix for now. Flagged as an open question in
  the Task 2 PR rather than decided unilaterally here, since it affects
  whether "what's free on VLAN 10" is actually queryable yet -- the core
  motivation section 5 gives for NetBox existing at all.
- Does not touch the UDM's DHCP fixed-reservation *write* endpoint --
  that's Task 5's `unifi_network_ip_reservation` role, an endpoint this
  plan's own pre-flight notes admit is still unverified.
- Never deletes a NetBox object, even one that no longer matches anything
  on the UDM.

## Variables

See `defaults/main.yml` for the full, heavily-commented list -- NetBox
connection + token location, UDM connection + credential location, the
external-dns ownership-filter prefix, the VLAN/prefix-length table, and
the documented low-address list itself.

## Running it

```sh
task ansible:run -- playbooks/netbox-import.yml --check --diff   # dry run first
task ansible:run -- playbooks/netbox-import.yml                  # real run
```

After running: spot-check a handful of the created/updated objects in the
NetBox UI (`/ipam/ip-addresses/`) against the UDM UI
(`Settings -> Internet -> DNS` for the static records, `Clients` for the
low-address list) -- plan Task 2 Step 5.
