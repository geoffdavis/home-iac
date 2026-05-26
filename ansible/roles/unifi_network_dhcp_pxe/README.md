# unifi_network_dhcp_pxe

Idempotent management of DHCP PXE-boot Options 66 (next-server / TFTP
server) and 67 (boot filename) on a named UniFi Network via the UDM
Pro / UniFi Network controller's REST API.

Mirrors the existing [`cloudflare_tunnel_ingress`](../cloudflare_tunnel_ingress/README.md)
role's pattern (controller-side, `delegate_to: localhost`, GET → diff
→ PUT only on drift, post-PUT re-query + assert outside `--check`).

## Why a role

UDM Pro DHCP options are click-ops by default. Putting them in Ansible
keeps the PXE next-server bound to whatever IP serves the netbootxyz
catalog app, so a host-side rename or migration doesn't silently
leave DHCP pointing at a dead TFTP server. The default
`unifi_network_dhcp_pxe_next_server` is `{{ truenas_netbootxyz_app_lan_ip }}` —
the two values can't drift.

## Credentials

The role expects a single 1Password item with `username` + `password`
fields. Default location: vault `Automation`, item
`UniFi UDM Pro (ansible)`. Override per-host via
`unifi_network_dhcp_pxe_creds_op_*`.

Create the credential once via the UniFi UI: Settings → Admins &
Users → Create New Admin. Role "Limited Admin" with site permissions
on the target site is sufficient (Owner works but is wider than
needed).

## Auth flow

UDM Pro uses cookie + CSRF, not bearer tokens:

1. `POST /api/auth/login` with `{username, password}` →
   `Set-Cookie: TOKEN=...` + `X-CSRF-Token: ...` response header
2. All subsequent calls include `Cookie:` (rebuilt from
   `cookies_string`) and `X-CSRF-Token:` headers
3. Best-effort `POST /api/auth/logout` at the end (failure is ignored
   — the PXE work is already done if we got there)

## API endpoints

- `GET /proxy/network/api/s/<site>/rest/networkconf` — list networks
  on the site. Response shape: `{ data: [<network>, ...] }`.
- `PUT /proxy/network/api/s/<site>/rest/networkconf/<id>` — partial
  update of one network. The controller merges the supplied fields
  into the stored config; unsupplied fields are preserved. The role
  PUTs only `{dhcpd_boot_enabled, dhcpd_boot_server, dhcpd_boot_filename}`
  so it can't accidentally rewrite VLAN / gateway / DNS-forwarder
  fields it doesn't manage.

## Drift handling

`_udm_pxe_needs_update` is computed by comparing the current values
of the three `dhcpd_boot_*` fields against the desired tuple. A PUT
only fires when they differ. After PUT, the role re-queries the
network and asserts the new values stick — guards against the rare
case where the controller returns 200 but persists nothing (e.g.
mid-config-save race with a concurrent UI edit).

`--check` mode runs the diff debug task but skips the PUT and the
verify-assert (the `uri` module no-ops non-GET in check mode, so
verifying would always fail on a drifted host).

## Variables

See `defaults/main.yml` for the full list. The interesting ones:

| Variable | Default | Purpose |
| --- | --- | --- |
| `unifi_network_dhcp_pxe_enabled` | `false` | Opt-in gate. |
| `unifi_network_dhcp_pxe_controller_url` | `https://172.29.50.1` | UDM Pro base URL. |
| `unifi_network_dhcp_pxe_validate_certs` | `false` | UDM ships a self-signed cert by default. |
| `unifi_network_dhcp_pxe_site` | `default` | UniFi site identifier (URL bar: `/manage/site/<this>/dashboard`). |
| `unifi_network_dhcp_pxe_target_network_name` | `LAN` | Display name of the network to configure (case-sensitive). |
| `unifi_network_dhcp_pxe_next_server` | `{{ truenas_netbootxyz_app_lan_ip }}` | DHCP Option 66 value. |
| `unifi_network_dhcp_pxe_boot_filename` | `netboot.xyz.efi` | DHCP Option 67 value (UEFI clients). |

## Failure modes worth knowing

- **CSRF token missing.** Very new UniFi OS releases have occasionally
  shifted the auth flow. The role asserts the CSRF token was returned
  and fail-fasts with a `curl` snippet so you can inspect the actual
  response headers.
- **Network not found.** The fail message lists the available network
  names, so you can pick the right one without going back to the UI.
  Most common cause is a non-default `unifi_network_dhcp_pxe_site`
  (the role defaults to "default", but the site identifier in
  multi-site installs is whatever shows up in the controller URL bar).
- **Cert validation failure.** The role defaults
  `validate_certs: false` because UDM Pro ships self-signed. If
  you've installed a trusted cert (Caddy / cert-manager / manual
  upload), flip it to `true` per host.

## Test plan

```bash
# Dry-run: shows current vs desired without applying
ansible-playbook playbooks/truenas-netbootxyz-app.yml \
  --limit nas-sdg --check

# Apply
ansible-playbook playbooks/truenas-netbootxyz-app.yml --limit nas-sdg

# Verify from the UDM UI: Settings → Networks → LAN → DHCP, scroll
# to "Network Boot" — should show Next Server = 172.29.50.20, Boot
# File = netboot.xyz.efi.

# Or via curl directly:
COOKIE=$(curl -sk -c - -X POST "https://172.29.50.1/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"...","password":"..."}' | grep TOKEN | awk '{print "TOKEN="$7}')

curl -sk "https://172.29.50.1/proxy/network/api/s/default/rest/networkconf" \
  -H "Cookie: $COOKIE" \
  | jq '.data[] | select(.name=="LAN") | {dhcpd_boot_enabled, dhcpd_boot_server, dhcpd_boot_filename}'
```
