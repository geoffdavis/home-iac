# freeipa_rsyslog

Forwards the FreeIPA replica VMs' (`ipa_replicas`) journals to the fleet
syslog catcher as RFC5424/TCP, and pins the VM timezone to UTC. This is
the VM half of nix-personal#200 — the NAS half lives in
`modules/nas/syslog-forward.nix` there.

## What it does

- **UTC pin** (`community.general.timezone`): RFC5424 timestamps carry an
  explicit offset either way, but local logs, cron, and cert-expiry math
  shouldn't depend on site TZ.
- **rsyslog install** (`dnf`): the VMs run journald-only today; Rocky's
  stock `/etc/rsyslog.conf` loads `imjournal` and reads the journal, so
  installing the package is all the journal→rsyslog wiring needed.
- **`/etc/rsyslog.d/30-forward-fleet-syslog.conf`** (template): a single
  `omfwd` forwarding action —
  - `RSYSLOG_SyslogProtocol23Format` (RFC5424) over TCP to
    `{{ freeipa_rsyslog_target }}:{{ freeipa_rsyslog_port }}`
    (default `syslog.ipa.geoffdavis.com:514`)
  - bounded in-memory queue (10k, discard from severity 6 at the 8k
    mark) + infinite retry every 10s — the catcher being down never
    wedges local logging, and low-severity messages are shed first
  - no `module(load=...)` directives: the base config owns module
    loading, the drop-in only adds the action
- **Local logging untouched**: `/var/log/messages` keeps working (Rocky
  default) — these VMs have no eMMC write-sparing concern.

## Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `freeipa_rsyslog_target` | `syslog.ipa.geoffdavis.com` | Fleet syslog catcher hostname |
| `freeipa_rsyslog_port` | `514` | Catcher TCP port |

## Usage

```sh
cd ansible && uv run ansible-playbook -i inventory.yml \
  playbooks/freeipa-rsyslog.yml --private-key ~/.ssh/op-ansible-ssh-key.pub
```

Idempotent; safe to re-run. The catcher-side listener and the
`syslog.ipa.geoffdavis.com` DNS record are managed elsewhere
(nix-personal#200 / `playbooks/freeipa-dns-records.yml`).
