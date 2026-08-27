# netbox_import_udm_dns_records

**One-shot** backfill of the UDM's current static-DNS list into the
`netbox-dns` plugin's `Record` objects, in the `home.geoffdavis.com` Zone
(id 1, View `Internal`, id 2). This is plan Task 8 Step 3 of
[`docs/superpowers/plans/2026-08-21-netbox-udm-sync.md`](../../../docs/superpowers/plans/2026-08-21-netbox-udm-sync.md)
— read that task's full section (including the Step 1-2 status notes)
before touching this role; the history and the credential story below are
explained there in more depth.

Idempotent (GET → diff → create/update, same shape as
[`netbox_import_udm_state`](../netbox_import_udm_state/README.md) and
[`unifi_network_dns_record`](../unifi_network_dns_record/README.md)) but
meant to run once — or be re-run by hand if UDM state drifts before Task
3/8's ongoing sync points at netbox-dns for real. **Never deletes
anything from NetBox** (the credential this role uses cannot delete —
see Credentials, below).

## Why a second backfill role (not just extending `netbox_import_udm_state`)

Task 2's `netbox_import_udm_state` backfills `ipam.IPAddress` objects —
the spec's stated fallback for when no DNS-record plugin exists. That
data model is A/AAAA-only and one-dns-name-per-address, so it silently
can't represent a CNAME, an NS record, a wildcard (`*.`) name, or a
record whose value isn't itself a NetBox-tracked IP address (the
netbird-overlay split-horizon pair, `100.92.233.103`, which NetBox's
IPAM has no reason to ever track). `netbox-dns` was installed and its
Zone created specifically to remove those limits (Task 8 Steps 1-2, done
live 2026-08-26) — this role targets that plugin's own `Record` model
instead, which has none of the fallback's structural gaps. Kept as a
separate role rather than folded into `netbox_import_udm_state` because
the two write to genuinely different NetBox object types
(`ipam.IPAddress` vs. `plugins.netbox_dns.Record`) with different
identity semantics (CIDR-string address vs. zone+type+name) — sharing a
role would mean branching most of `reconcile_one.yml` on which model is
in play, for no real code reuse benefit.

## Credentials

**Write-scoped, delete-free NetBox token** — a dedicated NetBox local
user `ansible` (id 4), with an `ObjectPermission` scoped to
`view`/`add`/`change` (**no delete**) on
`netbox_dns.{view,nameserver,zone,record}` only. Token at 1Password
`op://nas-overlay/netbox-ansible-service-account/credential` (vault
`nas-overlay`). Deliberately **not** Task 2's `netbox-udm-import-token`
(scoped for `ipam.IPAddress`, unconfirmed whether it even covers
`netbox_dns` object types) and **not** Task 3/8's future read-only
ongoing-sync token — same separation-of-scope rule the design doc uses
throughout. Live-verified 2026-08-26: succeeds on `netbox_dns`
reads/writes, 403s on `ipam.ipaddress` and `users` (the scoping is
actually restrictive, not just additive).

Two non-obvious things about this token, captured here because they cost
real debugging time when first minted (see the Task 8 status note in the
plan doc for the full story):

- `POST /api/users/tokens/` returns the secret split across **two**
  fields (`key`, a 12-char id, and `token`, the secret suffix) — the
  complete Bearer credential is the concatenation
  `"nbt_" + key + "." + token`.
- Use `Authorization: Bearer <token>` — not `Authorization: Token
  <token>` (the old v1 header format).

**UDM credentials** — same 1Password item every `unifi_network_*` role
and `netbox_import_udm_state` already use: vault `Automation`, item
`UniFi UDM Pro (ansible)`, fields `username` + `password`.

## Empirical API-shape findings (2026-08-26, verified live before writing the transform)

Per the plan's own instruction not to assume the plugin's field
semantics, one real test `Record` was created directly via the API
(`POST /api/plugins/netbox-dns/records/`) for each of an A record, a
wildcard A record, and a CNAME, before any of this role's transform
logic was written:

- **`name` is the record's bare label *relative to the zone*, not the
  full FQDN.** POSTing `{"zone": 1, "type": "A", "name":
  "backfill-shape-test", "value": "172.29.10.253", ...}` returned
  `"name": "backfill-shape-test"` and a separately computed
  `"fqdn": "backfill-shape-test.home.geoffdavis.com."` — `fqdn` is
  read-only/derived, not something you POST. This role's transform
  therefore strips the zone suffix (`.home.geoffdavis.com`) off each UDM
  `key` to build `name`.
- **Wildcards use the literal `*` prefix in the relative label**, exactly
  like the UDM's own convention — `"name": "*.nas-backfill-shape-test"`
  round-tripped as `"fqdn": "*.nas-backfill-shape-test.home.geoffdavis.com."`
  with no special encoding needed. `*.nas` / `*.admin` / `*.media` map
  straight across.
- **`value` for a CNAME wants a trailing-dot, fully-qualified target** —
  `"value": "nas-sdg.iot.home.geoffdavis.com."` round-tripped unchanged.
  The UDM's own static-DNS `value` field has no trailing dot
  (`nas-sdg.iot.home.geoffdavis.com`), so this role appends one for any
  name-shaped value (`CNAME`/`NS`/`MX`) that doesn't already have it. A/AAAA
  values are plain IP literals and are passed through untouched.
- **`ttl: null` is a valid, accepted value** — confirmed live on the
  zone's own auto-managed NS record, which carries `"ttl": null`
  (inherits the zone's `default_ttl`, 3600). The UDM reports `ttl: 0` for
  a static-DNS record whose TTL was never explicitly set (an "Auto"
  sentinel, not a real request for a 0-second TTL) — this role maps
  UDM `ttl: 0` → netbox-dns `ttl: null` rather than asserting a bogus
  literal 0.
- **The list endpoint supports `zone_id` + `type` + `name` filtering
  together** — `GET
  /api/plugins/netbox-dns/records/?zone_id=1&type=A&name=<label>`
  returns exactly the matching record(s). This is the identity this
  role's `reconcile_one.yml` GETs on before deciding create vs. update.

The three test records were deleted... **partially.** Two admin-level
deletes went through; the sandbox this backfill was implemented under
blocks any `DELETE` issued with the elevated (superuser) NetBox
credential as a matter of policy, regardless of target. **As of this
role's initial commit, up to three records with `description` empty and
`name` matching `backfill-shape-test`, `*.nas-backfill-shape-test`, or
`backfill-cname-test` may still exist in the `home.geoffdavis.com` zone
and need a human to delete them by hand** (NetBox UI → DNS → Records, or
`DELETE /api/plugins/netbox-dns/records/<id>/` with a token that has
delete rights) — they are obviously named as test artifacts, not part of
the real static-DNS import below, and are excluded from this role's own
desired-state list (this role never touches a record by name unless
that name is derived from a live UDM `key`).

## What it imports

**Everything on the UDM's live static-DNS list** (`GET
/proxy/network/v2/api/site/default/static-dns`, same endpoint/auth
`unifi_network_dns_record` and `netbox_import_udm_state` already use) —
every `record_type`, not just A/AAAA — **except**:

1. **Two explicit, by-name skips** (`defaults/main.yml`,
   `netbox_import_udm_dns_records_explicit_skip_keys`):
   - `ipa.geoffdavis.com` (`NS`, value `172.29.50.21`) — a genuinely
     different zone from `home.geoffdavis.com`, not a subdomain of it.
     FreeIPA owns its own DNS for that zone (see
     `playbooks/freeipa-dns-records.yml`). The value is also an IP
     address, an odd shape for an NS record's target regardless.
   - `pottedpork-hassio.duckdns.org` (`A`, value `172.29.50.157`) — a
     different domain entirely (`duckdns.org`, not
     `home.geoffdavis.com`); pinned locally so LAN clients don't hairpin
     out to the public DuckDNS record, but has no home in this zone.
2. **Anything `external-dns` (pi-talos-home-ops's Kubernetes controller)
   owns** — identified the same way Task 2's backfill identifies it: any
   `TXT` record shaped `_externaldns.a-<name>` →
   `...heritage=external-dns...` marks `<name>` as Kubernetes-managed,
   not static desired state. Both the target `A`/`AAAA` record **and**
   the `TXT` marker record itself are excluded — importing either would
   let a future NetBox→UDM sync collide with live Kubernetes
   reconciliation. Confirmed live 2026-08-26: this excludes
   `website-dev.k8s`, `website-prod.k8s`, and `hubble.k8s` (all →
   `172.29.55.0`, the Cilium LoadBalancer pool's *network* address, not
   a real host — consistent with `host_vars/nas-sdg.yml`'s own "SUSPECT"
   comment on the first two) plus their three `_externaldns.a-*` TXT
   markers.

Live run on 2026-08-26 imported **13 records**: 1 `CNAME`
(`syslog.home.geoffdavis.com`), and 12 `A` records — including the two
wildcards (`*.nas`, `*.admin`) plus `*.media`, the split-horizon
`nas`/`admin` pair pointing at the netbird overlay address
`100.92.233.103` (no IPAM presence, and none needed — a netbox-dns
`Record`'s `value` is just a string), `media`/`homeassistant.media`,
`k8s`, and three `.mgmt` host aliases (`nas-sdg`, `tourmaline`,
`pacificbeach`) plus `netbox.mgmt.home.geoffdavis.com` — the last two
of which are **not** in `host_vars/nas-sdg.yml`'s declared list at all
(added directly on the UDM after Task 1's `host_vars` capture — a live
reminder that the UDM, not `host_vars`, is this role's actual source of
truth, same as Task 2).

## What it does NOT do

- Does not create the Zone/View/NameServer — those already exist (Task 8
  Steps 1-2). This role only writes `Record` objects into
  `netbox_import_udm_dns_records_netbox_zone_id`.
- Does not touch `ipam.IPAddress` at all — that's Task 2's
  `netbox_import_udm_state`, a separate role/play in the same
  `playbooks/netbox-import.yml`.
- Does not delete a NetBox `Record`, even one that no longer matches
  anything on the UDM, or the leftover test records described above —
  the token this role uses cannot delete.
- Does not write anything back to the UDM. One-way, UDM → NetBox, same
  as every other backfill in this plan.

## Variables

See `defaults/main.yml` for the full, heavily-commented list — NetBox
connection + zone id/name + token location, UDM connection + credential
location, the external-dns ownership-filter prefix, and the explicit
skip-key list.

## Running it

```sh
task ansible:run -- playbooks/netbox-import.yml --check --diff --tags dns-records   # dry run first
task ansible:run -- playbooks/netbox-import.yml --tags dns-records                  # real run
```

(`--tags dns-records` scopes the run to this role's play only, leaving
Task 2's `netbox_import_udm_state` play alone; omit the tag to run both.)

The dry-run's `debug` output (`_nb_dns_desired` in `tasks/main.yml`, plus
the per-record current-vs-desired `debug` in `reconcile_one.yml`) is the
"dry survey" this role relies on in place of a real `--check` mode for
the plugin's custom endpoints — `uri` module `POST`/`PATCH` tasks are
skipped automatically under `--check`, so the survey's printed desired
list is the actual thing to read before trusting a real run.

After running: spot-check a handful of the created/updated records in
the NetBox UI (`/plugins/netbox-dns/records/`, filtered to the
`home.geoffdavis.com` zone) against the UDM UI (`Settings → Internet →
DNS`) — same discipline Task 2 Step 5 and Task 8 Step 3's own process
required. `dig +short <name>.home.geoffdavis.com @172.29.50.1` against a
few of the imported names (especially a wildcard) is a good live check
that this role's `name`/`fqdn` split matches what the UDM actually
answers.
