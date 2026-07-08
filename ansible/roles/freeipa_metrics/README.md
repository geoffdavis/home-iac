# freeipa_metrics

node_exporter + ipa-healthcheck textfile metrics on the FreeIPA replica
VMs (`ipa_replicas`), scraped over the netbird overlay by the
VictoriaMetrics hub on nas-sdg (nix-personal#153 Phase 3).

## What it installs

- **node_exporter** (upstream release binary, pinned + checksummed in
  `defaults/main.yml` — EPEL10 does not package it as of 2026-07-08) as a
  systemd service on `:9100` with the systemd collector and a textfile
  collector dir at `/var/lib/node_exporter/textfile`. Versioned install
  under `/opt/node_exporter-<ver>...` with a `/usr/local/bin` symlink —
  bumping version+checksum and re-running the playbook upgrades cleanly.
- **ipa-healthcheck-metrics** (script + oneshot service + 30-min timer):
  runs `ipa-healthcheck --output-type json` as root and emits:
  - `ipa_healthcheck_results_total{severity}` — counts per severity
  - `ipa_healthcheck_failed{source,check,severity}` — one series per
    non-SUCCESS check (empty on a healthy replica)
  - `ipa_healthcheck_cert_days_min` — minimum days-to-expiry across all
    checks reporting a `days` kw (the silent-cert-expiry signal)
  - `ipa_healthcheck_{exit_code,parse_ok,last_run_timestamp_seconds,duration_seconds}`

## Reachability / firewall

No firewall changes: the VMs' netbird interface (`wt0`) is in firewalld's
`trusted` zone, while the LAN/NAT interface stays in `public` (blocks
9100). The hub scrapes `ipa-<site>-replica.netbird.cloud:9100`; nothing
is exposed beyond the overlay.

## Usage

```sh
cd ansible && uv run ansible-playbook -i inventory.yml \
  playbooks/freeipa-metrics.yml --private-key ~/.ssh/op-ansible-ssh-key.pub
```

Idempotent; safe to re-run. Hub-side scrape job, dashboard tile, and
alert rules live in nix-personal (`hosts/nas-sdg/monitoring-hub.nix` /
`alerting.nix`).
