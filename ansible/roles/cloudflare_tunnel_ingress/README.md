# cloudflare_tunnel_ingress

Keeps a per-host Cloudflare Tunnel's ingress rules in sync with what
the host actually serves. Complement to `scripts/cf-deadman-bootstrap.py`:

| | `cf-deadman-bootstrap.py` | `cloudflare_tunnel_ingress` role |
| --- | --- | --- |
| When | One-shot, when a tunnel is first created | Every Ansible bootstrap run |
| Owns | Tunnel creation, DNS CNAME bootstrap, Access app + service token setup, 1P token storage | The tunnel's `config.ingress` list |
| Idempotent re-run | Yes (re-detects + reuses) | Yes (GET → diff → PUT-on-drift) |
| Driven by | Hardcoded list in the script | `cloudflare_tunnel_ingress_rules` in host_vars |

After this role exists, the bootstrap script's hardcoded ingress
config is effectively a seed — actual ongoing routing changes flow
through this role's per-host inventory.

## What this role does

Runs entirely controller-side (`delegate_to: localhost` on every
task — there's nothing host-local to do; the tunnel's ingress lives
in Cloudflare's edge):

1. Fetches the Cloudflare API token from 1P per-host. (An earlier
   draft used `run_once: true` for a single fetch across the play,
   but Ansible facts are host-scoped regardless of `run_once`, so
   subsequent hosts would have hit `_cf_api_token` undefined. The
   per-host pattern relies on the 1P CLI's session caching to avoid
   repeated biometric prompts — usually still one prompt total per
   session.)
2. Looks up the tunnel by name (default: `inventory_hostname`)
3. GETs the current ingress + warp-routing config
4. Computes desired ingress (`cloudflare_tunnel_ingress_rules` + the
   catchall, appended last)
5. Diffs desired vs current
6. PUTs the new config **only on drift** (preserves `warp-routing`
   from the current config so the role doesn't accidentally clear it)
7. Re-GETs to verify the PUT actually took effect

## Why this role (vs. extending the bootstrap script)

The bootstrap script is a sequential procedure with sensible
defaults baked in (every NAS gets SSH on port 22 + UGOS UI on 9443).
That worked when every NAS was UGOS, but post-TrueNAS-migration each
host's ingress diverges:

- UGOS hosts: keep `https://localhost:9443` (UGOS UI port)
- TrueNAS hosts: switch to `https://localhost:443` (TrueNAS UI port)
- Future hosts: TBD on what they serve

Extending the bootstrap script to be platform-aware works but
couples ingress maintenance to the rest of the bootstrap procedure
(tunnel creation, DNS, Access apps). Splitting it out:
- Lets per-host inventory drive routing (declarative, diffable in PR review)
- Gives `--check` mode a dry-run preview of ingress drift
- Slots into the rest of the Ansible toolchain (matches the
  `truenas_*_app` role pattern)
- Bootstrap script stays focused on one-shot setup

## Variables

See `defaults/main.yml`. The variable you actually need per-host:

| Variable | Purpose |
| --- | --- |
| `cloudflare_tunnel_ingress_rules` | **Required.** Ordered list of ingress rules (without catchall). Each rule: `{hostname, service[, originRequest, path]}`. Order matters — Cloudflare matches first-rule-wins. |

Other variables (rarely overridden):

| Variable | Purpose |
| --- | --- |
| `cloudflare_tunnel_ingress_tunnel_name` | Default `inventory_hostname`. The Cloudflare-side tunnel name to manage. |
| `cloudflare_tunnel_ingress_catchall` | Default `{service: http_status:404}`. Appended last to the rules list. |
| `cloudflare_tunnel_ingress_account_id` | Account ID (rarely changes). |
| `cloudflare_tunnel_ingress_token_op_item` | 1P item name. Default `Cloudflare API Token (ansible)` in vault `Automation`. Same item `cf-deadman-bootstrap.py` uses. |
| `cloudflare_tunnel_ingress_require_real_upstream` | Default `true`. Safety guard: refuses to PUT an ingress that's catchall-only (would brick the tunnel). Set false only when intentionally retiring a tunnel. |

## Example host_vars

```yaml
# host_vars/nas-sct.yml — TrueNAS host
cloudflare_tunnel_ingress_rules:
  - hostname: "ssh-nas-sct.geoffdavis.com"
    service: "tcp://localhost:22"
  - hostname: "ugos-nas-sct.geoffdavis.com"  # legacy name retained
    service: "https://localhost:443"          # TrueNAS UI port
    originRequest:
      noTLSVerify: true
```

```yaml
# host_vars/nas-cin.yml — UGOS host (before migration)
cloudflare_tunnel_ingress_rules:
  - hostname: "ssh-nas-cin.geoffdavis.com"
    service: "tcp://localhost:22"
  - hostname: "ugos-nas-cin.geoffdavis.com"
    service: "https://localhost:9443"         # UGOS UI port
    originRequest:
      noTLSVerify: true
```

When `nas-cin` migrates to TrueNAS, the change is a one-line
host_vars edit: `9443` → `443`. The role re-runs, detects drift,
PUTs the new config, cloudflared picks it up within seconds.

## Pre-requisites

- The tunnel must already exist (`cf-deadman-bootstrap.py` must have
  been run once for the host). The role fails fast if it can't find
  a tunnel matching `cloudflare_tunnel_ingress_tunnel_name`.
- Cloudflare API token in 1P at the configured vault/item.
- `kubernetes.core` collection NOT required (uses `ansible.builtin.uri`).

## Safety guards

- **Empty rules list bails**: the role refuses to PUT an ingress
  consisting only of the catchall (would point the tunnel at
  nothing-but-404, almost always a mistake — typo'd host_vars,
  missing inventory file).
- **All-404 rules list bails**: same reasoning. Set
  `cloudflare_tunnel_ingress_require_real_upstream: false` to
  intentionally retire a tunnel's routing.
- **`warp-routing` preserved**: the role doesn't manage warp-routing
  config; the PUT copies the current value through so warp-routing
  enable/disable isn't accidentally flipped.
- **PUT-then-verify**: after a successful PUT, the role re-GETs and
  asserts the new ingress matches what was sent — guards against
  the (unlikely) case where Cloudflare returns 200 but persists
  nothing.

## --check mode

Running the playbook with `--check` runs the GET + diff but skips
the PUT. The debug task surfaces the diff so the operator sees
exactly what would change. Useful for previewing host_vars edits
before applying.

```sh
ansible-playbook playbooks/truenas-bootstrap.yml --limit nas-sct --check --diff
```

## Relationship to other tunnel-handling roles

- `cloudflared` (UGOS) / `truenas_cloudflared_app` (TrueNAS): bring
  the connector container up on the host. Consume the install token
  from 1P. The connector watches Cloudflare for config changes and
  applies them within seconds.
- `cloudflare_tunnel_ingress` (this role): controls the
  Cloudflare-side ingress config that the connector watches.

The pair is decoupled — connector and ingress can be updated
independently — but together they own the full tunnel state.
