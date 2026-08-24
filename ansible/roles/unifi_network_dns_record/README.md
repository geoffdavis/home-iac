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

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `unifi_network_dns_record_enabled` | `false` | Opt-in gate |
| `unifi_network_dns_record_controller_url` | `https://172.29.50.1` | UDM base URL |
| `unifi_network_dns_record_validate_certs` | `false` | UDM ships self-signed |
| `unifi_network_dns_record_site` | `default` | UniFi site identifier |
| `unifi_network_dns_record_creds_op_item` | `UniFi UDM Pro (ansible)` | 1P item name |
| `unifi_network_dns_record_creds_op_vault` | `Automation` | 1P vault name |
| `unifi_network_dns_record_records` | `[]` | List of record dicts (see below) |

### Record dict fields

| Field | Required | Default | Description |
|---|---|---|---|
| `record_type` | yes | — | `A` \| `AAAA` \| `CNAME` \| `MX` \| `TXT` \| ... |
| `key` | yes | — | Record FQDN; idempotency key (with `record_type`) |
| `value` | yes | — | Record target (IP for A, hostname for CNAME, ...) |
| `enabled` | no | `true` | Record active |
| `state` | no | `present` | `present` or `absent` |

## Example — central syslog CNAME

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
