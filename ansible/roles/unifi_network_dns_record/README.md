# unifi_network_dns_record

Idempotent management of static DNS records on a UDM Pro / UniFi
Network controller via the REST API, **sourced from NetBox** instead of
Ansible `host_vars`. Runs entirely controller-side
(`delegate_to: localhost`).

Rewritten here from the [`ugreen-nas-compose` original][orig] per
[home-iac#8][issue] (tracking
[geoffdavis/ugreen-nas-compose#250][ugreen-250]) and
[`docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md`][spec].
The UDM-side auth flow and per-record diff/PUT logic
(`reconcile_one.yml`) are **unchanged** — what's new is where the
desired-record list comes from, plus the full symmetric-set comparison
and `external-dns` ownership exclusion the design doc requires.

[orig]: https://github.com/geoffdavis/ugreen-nas-compose/blob/main/ansible/roles/unifi_network_dns_record/
[issue]: https://github.com/geoffdavis/home-iac/issues/8
[ugreen-250]: https://github.com/geoffdavis/ugreen-nas-compose/issues/250
[spec]: ../../../docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md

## Motivation

Publishes stable names in the UDM-authoritative internal zone
(`home.geoffdavis.com`) for services whose backing host may move — e.g.
the central syslog endpoint (`syslog.home.geoffdavis.com` →
VictoriaLogs on nas-sdg). The record list used to live in `host_vars`,
hand-run "on a schedule nobody but [the old] repo knows" — see the spec's
Why section. NetBox is now that source of truth; editing a record means
editing NetBox, then syncing.

## Sync model

One direction only: **NetBox → UDM**. The comparison is a full,
symmetric set comparison, not a one-directional walk over NetBox's
desired list (spec: "Sync direction and idempotency"):

1. **Set A** — every `key`+`record_type` NetBox says should exist,
   filtered to `unifi_network_dns_record_managed_zone_suffix` and minus
   any name the ownership filter (below) excludes.
2. **Set B** — every `key`+`record_type` currently on the UDM, same
   zone filter and exclusion.
3. In A, not in B → create. In both, differ → update. In both, match →
   no-op. **In B, not in A → logged loudly, never auto-deleted** — either
   backfill it into NetBox, or remove it by hand on the UDM.

### `external-dns` ownership exclusion

`pi-talos-home-ops`'s Cilium/`external-dns` writes its own records into
this same zone, marked with a TXT ownership record (heritage
`external-dns`). Any UDM `key` carrying such a TXT sibling is excluded
from **both** set A and set B before anything else runs — this role can
never create, update, or even report-as-orphan a Kubernetes-owned name,
even if NetBox happens to hold a record with the same key+type.

**Not verified against a live controller yet.** The exclusion looks for
any TXT record whose `value` contains
`unifi_network_dns_record_external_dns_heritage_marker` (default
`heritage=external-dns`, external-dns's default TXT-registry
convention). Confirm this actually matches what `external-dns` writes on
the real UDM before trusting `source: netbox` against records anywhere
near the `k8s.home…` zone.

## NetBox source

- **Endpoint**: `unifi_network_dns_record_netbox_records_endpoint`
  (default `/api/plugins/netbox-dns/records/`) — the `netbox-dns` plugin
  is the spec's candidate DNS model; core NetBox has no zone/record
  object. **Implementation-time decision, not yet confirmed** — verify
  the plugin is actually installed and this shape matches once
  [nix-personal#542][np542] (NetBox hosting) lands. If it isn't, the
  documented fallback is `ipam.IPAddress`'s built-in `dns_name` field
  (A/AAAA only), which needs its own query + transform, not a variant of
  this endpoint.
- **Auth**: a **read-only** NetBox API token, 1Password-sourced
  (`unifi_network_dns_record_netbox_creds_op_item`). This must be a
  *different* 1Password item than the write-scoped token
  `netbox_import_udm_state` (the one-shot backfill role) uses — the
  ongoing sync never holds write access to NetBox.
- **Pagination**: NetBox list endpoints paginate
  (`{count, next, previous, results}`); the role follows `next` up to
  `unifi_network_dns_record_netbox_max_pages` pages of
  `unifi_network_dns_record_netbox_page_limit` records each.

## Escape hatch

`unifi_network_dns_record_source: static` (default `netbox`) switches
back to a fixed `unifi_network_dns_record_records` list, the same shape
the original `host_vars`-driven role used. This exists because NetBox
itself doesn't run yet ([nix-personal#542][np542] is still in flight) —
it's how this role is exercised today, and is the escape hatch plan Task
6 retires once NetBox-sourced syncs are proven clean in production.

[np542]: https://github.com/geoffdavis/nix-personal/issues/542

## Credentials

- **UDM**: same 1Password item the other `unifi_network_*` roles use —
  vault `Automation`, item `UniFi UDM Pro (ansible)`, fields `username` +
  `password`.
- **NetBox**: see above — read-only token, own 1Password item.

## API endpoints (UDM side, unchanged from the original)

Static DNS lives under the **v2** API:

- `GET /proxy/network/v2/api/site/<site>/static-dns` — list records
- `POST /proxy/network/v2/api/site/<site>/static-dns` — create
- `PUT /proxy/network/v2/api/site/<site>/static-dns/<_id>` — update
- `DELETE /proxy/network/v2/api/site/<site>/static-dns/<_id>` — delete
  (only reachable via the static escape hatch's `state: absent` — the
  NetBox path never deletes; see Sync model)

Two v2 quirks the role accounts for: the list endpoint returns a bare
JSON array (no v1 `{data: [...]}` envelope), and mutations return the
record object directly (asserted on the returned `_id`, not an `rc`
envelope).

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `unifi_network_dns_record_enabled` | `false` | Opt-in gate |
| `unifi_network_dns_record_controller_url` | `https://172.29.50.1` | UDM base URL |
| `unifi_network_dns_record_validate_certs` | `false` | UDM ships self-signed |
| `unifi_network_dns_record_site` | `default` | UniFi site identifier |
| `unifi_network_dns_record_creds_op_item` / `_op_vault` | UDM item/vault | 1P UDM creds |
| `unifi_network_dns_record_source` | `netbox` | `netbox` or `static` |
| `unifi_network_dns_record_records` | `[]` | Static escape-hatch record list (`source: static` only) |
| `unifi_network_dns_record_netbox_url` | `https://netbox.home.geoffdavis.com` | NetBox base URL |
| `unifi_network_dns_record_netbox_validate_certs` | `true` | NetBox cert validation |
| `unifi_network_dns_record_netbox_creds_op_item` / `_op_vault` | NetBox read-only token item/vault | 1P NetBox creds |
| `unifi_network_dns_record_netbox_records_endpoint` | `/api/plugins/netbox-dns/records/` | DNS-plugin list endpoint |
| `unifi_network_dns_record_netbox_zone` | `home.geoffdavis.com` | NetBox zone name to sync |
| `unifi_network_dns_record_netbox_page_limit` / `_max_pages` | `200` / `20` | Pagination bounds |
| `unifi_network_dns_record_managed_zone_suffix` | `home.geoffdavis.com` | Zone this sync owns on the UDM side |
| `unifi_network_dns_record_external_dns_heritage_marker` | `heritage=external-dns` | Ownership-exclusion TXT marker |

### Static-escape-hatch record dict fields

Same shape as the original role: `record_type`, `key`, `value`
(required), `enabled` (default `true`), `state` (default `present`).

## Known gaps

- **Live NetBox testing is pending [nix-personal#542][np542].** This
  role is written against `netbox-dns`'s documented API shape but has
  never queried a running NetBox instance. Verify Gate G3 (`--check`,
  zero diffs) for real once NetBox exists and is backfilled.
- **The `external-dns` TXT-marker match is unverified** — see "Sync
  model" above.
- **`nas-cin` is currently offline** (fleet outage, ongoing as of this
  PR). Any backfill or live verification pass should skip records tied
  to `nas-cin` rather than treat it as reachable — this role has no
  hardcoded per-site data, so nothing here blocks on it, but the Task 2
  backfill and Task 3 Step 7/8 live checks (not part of this PR) will
  need to account for it when they run.

## Failure modes

- **Record not found on DELETE**: no-op, not an error (static escape
  hatch only)
- **POST/PUT response missing `_id`**: loud assertion failure with raw
  response
- **CSRF token missing**: curl the login endpoint with `-i` and check
  headers
- **NetBox record missing `type`/`value`**: `netbox_dns_records_to_udm`
  will raise a `KeyError` — a deliberately loud failure rather than
  silently skipping a malformed NetBox object
