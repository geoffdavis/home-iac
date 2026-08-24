# unifi_network_port_forward

Idempotent management of port-forward rules on a UDM Pro / UniFi
Network controller via the REST API. Runs entirely controller-side
(`delegate_to: localhost`).

Mirrors the [`unifi_network_dhcp_pxe`](../unifi_network_dhcp_pxe/README.md)
role's structure: same UDM cookie + CSRF auth flow, same GET→diff→mutate
pattern, same 1Password credential convention.

## Motivation

Enables direct Netbird peer-to-peer connections without going through a
relay. When a NAS has a fixed WireGuard port (set via
`truenas_netbird_app_wg_port`) AND a UDM port forward routes that UDP
port from the WAN to the NAS's LAN IP, other Netbird peers can reach
it directly via STUN/ICE, improving backup throughput between sites.

## Credentials

Shares the same 1Password item as `unifi_network_dhcp_pxe` — vault
`Automation`, item `UniFi UDM Pro (ansible)`, fields `username` +
`password`. A single UniFi "Limited Admin" account covers both roles.

## API endpoints

- `GET /proxy/network/api/s/<site>/rest/portforward` — list rules
- `POST /proxy/network/api/s/<site>/rest/portforward` — create
- `PUT /proxy/network/api/s/<site>/rest/portforward/<id>` — update
- `DELETE /proxy/network/api/s/<site>/rest/portforward/<id>` — delete

Identity for idempotency: the `name` field. A rule found by name is
compared field-by-field; a PUT only fires on drift.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `unifi_network_port_forward_enabled` | `false` | Opt-in gate |
| `unifi_network_port_forward_controller_url` | `https://172.29.50.1` | UDM base URL |
| `unifi_network_port_forward_validate_certs` | `false` | UDM ships self-signed |
| `unifi_network_port_forward_site` | `default` | UniFi site identifier |
| `unifi_network_port_forward_creds_op_item` | `UniFi UDM Pro (ansible)` | 1P item name |
| `unifi_network_port_forward_creds_op_vault` | `Automation` | 1P vault name |
| `unifi_network_port_forward_rules` | `[]` | List of rule dicts (see below) |

### Rule dict fields

| Field | Required | Default | Description |
|---|---|---|---|
| `name` | yes | — | Display label; idempotency key |
| `proto` | yes | — | `tcp` \| `udp` \| `tcp_udp` |
| `dst_port` | yes | — | External WAN port or range (`"51820"`) |
| `fwd` | yes | — | Internal destination IP |
| `fwd_port` | yes | — | Internal destination port |
| `src` | no | `any` | WAN source IP filter |
| `enabled` | no | `true` | Rule active |
| `log` | no | `false` | Log matching packets |
| `state` | no | `present` | `present` or `absent` |

## Example — Netbird WireGuard port forward

In `host_vars/nas-sdg.yml`:

```yaml
truenas_netbird_app_wg_port: "51820"

unifi_network_port_forward_enabled: true
unifi_network_port_forward_rules:
  - name: netbird-nas-sdg
    proto: udp
    src: any
    dst_port: "51820"
    fwd: "172.29.50.20"   # nas-sdg's LAN IP (the default-route interface)
    fwd_port: "51820"
```

After running the bootstrap playbook, verify direct connectivity:

```bash
# On a remote peer
netbird status --detail
# Look for "connection type: direct" for nas-sdg
```

If the app was already RUNNING before `truenas_netbird_app_wg_port` was
set, restart the container to pick up `NB_WIREGUARD_PORT`:

```bash
midclt call app.restart netbird-client   # on nas-sdg
```

## Failure modes

- **Rule not found on DELETE**: no-op, not an error
- **POST/PUT returns non-ok rc**: loud assertion failure with raw response
- **CSRF token missing**: same diagnosis path as `unifi_network_dhcp_pxe` —
  curl the login endpoint with `-i` and check headers
