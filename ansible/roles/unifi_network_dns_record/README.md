# unifi_network_dns_record

Idempotent management of static DNS records on a UDM Pro / UniFi
Network controller via the REST API. Runs entirely controller-side
(`delegate_to: localhost`).

Mirrors the [`unifi_network_port_forward`](../unifi_network_port_forward/README.md)
role's structure: same UDM cookie + CSRF auth flow, same GET→diff→mutate
pattern, same 1Password credential convention.

## Motivation

Publishes stable names in the UDM-authoritative internal zone
(`home.geoffdavis.com`) for services whose backing host may move —
e.g. the central syslog endpoint (`syslog.home.geoffdavis.com` →
VictoriaLogs on nas-sdg). LAN senders keep pointing at the alias; a
host move is a one-line record change here instead of a fleet-wide
client reconfiguration.

## Credentials

Shares the same 1Password item as the other `unifi_network_*` roles —
vault `Automation`, item `UniFi UDM Pro (ansible)`, fields `username` +
`password`. A single UniFi "Limited Admin" account covers all three
roles.

## API endpoints

Static DNS lives under the **v2** API (unlike port-forwards, which use
the v1 `/api/s/<site>/rest/...` namespace):

- `GET /proxy/network/v2/api/site/<site>/static-dns` — list records
- `POST /proxy/network/v2/api/site/<site>/static-dns` — create
- `PUT /proxy/network/v2/api/site/<site>/static-dns/<_id>` — update
- `DELETE /proxy/network/v2/api/site/<site>/static-dns/<_id>` — delete

Two v2 quirks the role accounts for:

- The list endpoint returns a **bare JSON array**, not the v1
  `{data: [...]}` envelope.
- Mutations return the record object (with `_id`) directly on success —
  there is no `{meta: {rc: "ok"}}` to assert on, so the role asserts on
  the returned `_id` (POST/PUT) and the HTTP 200 status (DELETE).

Identity for idempotency: `key` + `record_type` (the schema has no
name/description field, and one FQDN may carry records of several
types). A matched record is compared on `value` + `enabled`; a PUT only
fires on drift.

## Sync model

The role has two `unifi_network_dns_record_source` modes:

- **`static`** (default) — desired records come verbatim from
  `unifi_network_dns_record_records`, exactly as before this role had
  any NetBox awareness. One-directional: only the listed records are
  touched; `state: absent` entries are the explicit-delete mechanism.
  This is the safe, unchanged default — flipping a host to `netbox`
  mode is a deliberate per-host `host_vars` decision, not something
  this role defaults into.

- **`netbox`** — desired records (set A) come from the `netbox-dns`
  plugin's `Record` objects instead. Comparison against the UDM's
  current state (set B) is a **full symmetric set diff**, not a
  one-directional walk over set A — a one-directional walk would
  silently miss "in UDM, not in NetBox" records entirely. Both sets are
  zone-filtered (`unifi_network_dns_record_managed_zone_suffix`) and
  have `external-dns`-owned names excluded
  (`unifi_network_dns_record_external_dns_heritage_marker`) *before*
  the comparison, so this sync can never propose creating, updating, or
  orphan-reporting a Kubernetes-owned name — even on a key+type
  collision. Anything in set B but not set A is logged loudly as an
  orphan and left alone; **this role never deletes a record it
  discovers is no longer in NetBox.**

### Sourcing from `netbox-dns`'s `Record` objects

The design always called for sourcing from NetBox's `netbox-dns` plugin
if installed — this role originally shipped (PR #16) against
`ipam.IPAddress.dns_name` instead, the spec's documented *fallback*,
because the plugin wasn't installed yet (confirmed live 2026-08-24:
`GET /api/status/` → `"plugins":{}`). Plan Task 8 installed the plugin,
created the `home.geoffdavis.com` Zone, and backfilled its real
static-DNS data into `Record` objects
(`ansible/roles/netbox_import_udm_dns_records/`, 2026-08-26) — this
role now reads from that data directly (Task 8 Step 5), which removes
every limitation the `ipam.IPAddress` fallback had:

- **Every record type, not just A/AAAA** — `netbox-dns` models a
  `Record` as first-class `{zone, type, name, value, ttl, status}`, not
  something derived from an IP address, so `CNAME` (the syslog alias),
  wildcards (`*.nas`, `*.admin`, `*.media`), and the split-horizon `nas`
  / `admin` pair pointing at the netbird overlay address
  (`100.92.233.103`, which NetBox's IPAM has no reason to ever track)
  all sync correctly now instead of being silently invisible.
- The zone this role reads from is resolved by **name**, live, to a
  numeric zone id (`GET
  /api/plugins/netbox-dns/zones/?name=<managed_zone_suffix>`) rather
  than hardcoded — see the "Resolve netbox-dns zone id" task in
  `tasks/main.yml`.
- `netbox_dns_records_to_udm` (`filter_plugins/netbox_sync.py`) is the
  transform. It relies on empirically-verified `netbox-dns` field
  behavior — `fqdn` as a real, correct, server-computed trailing-dot
  FQDN (used directly, dot stripped); a CNAME/NS/MX `value`'s trailing
  dot (also stripped, to match the UDM's own dotless convention);
  `status` as a **plain string** (`"active"`), not the nested
  `{value, label}` shape `ipam.IPAddress.status` used; and `managed`
  (bool) marking the zone's own auto-generated SOA/apex-NS bookkeeping
  records, which are skipped unconditionally — see the function's
  docstring for the full detail and how each fact was confirmed live.
- The `ipam.IPAddress` fallback's "address with no `dns_name` set"
  skip case no longer applies — every `netbox-dns` `Record` in the zone
  is a real, addressable DNS record by construction.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `unifi_network_dns_record_enabled` | `false` | Opt-in gate |
| `unifi_network_dns_record_controller_url` | `https://172.29.50.1` | UDM base URL |
| `unifi_network_dns_record_validate_certs` | `false` | UDM ships self-signed |
| `unifi_network_dns_record_site` | `default` | UniFi site identifier |
| `unifi_network_dns_record_creds_op_item` | `UniFi UDM Pro (ansible)` | 1P item name |
| `unifi_network_dns_record_creds_op_vault` | `Automation` | 1P vault name |
| `unifi_network_dns_record_source` | `static` | `static` or `netbox` — see "Sync model" |
| `unifi_network_dns_record_records` | `[]` | List of record dicts (source: `static`, see below) |
| `unifi_network_dns_record_netbox_url` | `http://172.29.10.20:8080` | NetBox base URL (source: `netbox`) |
| `unifi_network_dns_record_netbox_host_header` | `netbox.mgmt.home.geoffdavis.com` | Explicit `Host` header (reached by IP, not name) |
| `unifi_network_dns_record_netbox_validate_certs` | `true` | NetBox cert validation |
| `unifi_network_dns_record_netbox_token_op_item` | `netbox-ansible-inventory-token` | 1P item — reuses the read-only inventory token (live-confirmed it can also read `netbox_dns.*`) |
| `unifi_network_dns_record_netbox_token_op_vault` | `nas-overlay` | 1P vault name |
| `unifi_network_dns_record_netbox_records_endpoint` | `/api/plugins/netbox-dns/records/` | netbox-dns Record list endpoint |
| `unifi_network_dns_record_netbox_page_limit` | `200` | Page size for pagination |
| `unifi_network_dns_record_netbox_max_pages` | `20` | Safety cap on pagination |
| `unifi_network_dns_record_managed_zone_suffix` | `home.geoffdavis.com` | The netbox-dns Zone this sync reads from (resolved by name to an id live) **and** the suffix `set B` is scoped to |
| `unifi_network_dns_record_external_dns_heritage_marker` | `heritage=external-dns` | TXT-record substring marking a name as Kubernetes-owned |

### Record dict fields

| Field | Required | Default | Description |
|---|---|---|---|
| `record_type` | yes | — | `A` \| `AAAA` \| `CNAME` \| `MX` \| `TXT` \| ... |
| `key` | yes | — | Record FQDN; idempotency key (with `record_type`) |
| `value` | yes | — | Record target (IP for A, hostname for CNAME, ...) |
| `enabled` | no | `true` | Record active |
| `state` | no | `present` | `present` or `absent` |

## Example — NetBox-sourced sync

In `host_vars/nas-sdg.yml`:

```yaml
unifi_network_dns_record_enabled: true
unifi_network_dns_record_source: netbox
```

Every run: resolve the `home.geoffdavis.com` netbox-dns Zone by name,
fetch its `Record` objects, transform to the UDM record shape (every
type netbox-dns supports, not just A/AAAA), diff against the UDM's
current `home.geoffdavis.com` records (excluding anything
`external-dns` owns), reconcile drift, and log — but never delete —
anything left on the UDM that NetBox no longer lists.

## Example — static CNAME

In `host_vars/nas-sdg.yml`:

```yaml
unifi_network_dns_record_enabled: true
unifi_network_dns_record_records:
  - record_type: CNAME
    key: syslog.home.geoffdavis.com
    value: nas-sdg.iot.home.geoffdavis.com
    state: present
```

After running `playbooks/unifi-network.yml`, verify from a LAN client:

```bash
dig +short syslog.home.geoffdavis.com @172.29.50.1
# → nas-sdg.iot.home.geoffdavis.com. followed by its A record
```

## Failure modes

- **Record not found on DELETE**: no-op, not an error
- **POST/PUT response missing `_id`**: loud assertion failure with raw
  response
- **CSRF token missing**: same diagnosis path as the other
  `unifi_network_*` roles — curl the login endpoint with `-i` and check
  headers
