# freeipa_autopatch

Makes the FreeIPA replica VMs self-patch between full rebuilds. Runs **on the
VMs** (the `ipa_replicas` inventory group), not on the TrueNAS host — the
`truenas_freeipa_vm` role provisions the VM from the host side and cannot
reach inside it.

## Why

The IPA replicas (`ipa-sdg`, `ipa-sct`, `ipa-cin` — Rocky Linux 10 libvirt/KVM
VMs) are "cattle": the design intent is to upgrade by replacing a replica every
3–5 years rather than patching in place (see
[`docs/superpowers/specs/2026-05-18-freeipa-incus-vm-design.md`](../../../docs/superpowers/specs/2026-05-18-freeipa-incus-vm-design.md)).
That covers major versions but leaves a gap for routine **security patching**
(kernel/glibc/openssl CVEs) and for keeping the **netbird** client current. This
role closes that gap.

## What it does

1. **dnf-automatic, security-only.** Installs `dnf-automatic`, writes
   `/etc/dnf/automatic.conf` with `upgrade_type = security` +
   `apply_updates = yes`, and pins `dnf-automatic.timer` (drop-in) to run
   before the reboot windows (default 02:00).
2. **Daily netbird upgrade.** netbird's RPM repo carries no security
   updateinfo, so security-only dnf-automatic skips it. A dedicated
   `freeipa-netbird-update.timer` runs `dnf -y upgrade netbird` daily and
   restarts the daemon **only if the package actually changed** (a netbird
   restart briefly blips the `wt0` overlay → a few seconds of replication /
   Kerberos pause).
3. **Staggered post-patch reboot.** `freeipa-autoreboot.timer` runs
   `needs-restarting -r` (from `dnf-utils`) and reboots **only when a reboot is
   actually required**. Windows are staggered per site so the mesh never loses
   two replicas at once — with the defaults: `sdg` 04:30, `sct` 05:30,
   `cin` 06:30 (`base_hour` + per-site offset, `RandomizedDelaySec` jitter on
   top).

New VMs get the dnf-automatic security baseline directly from the
`truenas_freeipa_vm` cloud-init template, so they self-patch from first boot;
this role is the re-runnable source of truth that converges existing VMs and
adds the netbird + staggered-reboot timers on top.

## Usage

```bash
ansible-playbook -i inventory.yml playbooks/freeipa-autopatch.yml
# or a single replica:
ansible-playbook -i inventory.yml playbooks/freeipa-autopatch.yml --limit ipa-sct
```

Run it as part of replica bring-up, after `freeipa-install.yml`.

## Variables

All optional — see [`defaults/main.yml`](defaults/main.yml) and
[`meta/argument_specs.yml`](meta/argument_specs.yml). Highlights:

| Var | Default | Notes |
|---|---|---|
| `freeipa_autopatch_security_enabled` | `true` | dnf-automatic security patching |
| `freeipa_autopatch_security_oncalendar` | `*-*-* 02:00:00` | keep before reboot windows |
| `freeipa_autopatch_netbird_enabled` | `true` | daily netbird upgrade |
| `freeipa_autopatch_netbird_oncalendar` | `*-*-* 03:00:00` | |
| `freeipa_autopatch_reboot_enabled` | `true` | staggered post-patch reboot |
| `freeipa_autopatch_reboot_base_hour` | `4` | window = base + per-site offset |
| `freeipa_autopatch_reboot_minute` | `30` | |
| `freeipa_autopatch_reboot_site_offset_hours` | `{sdg: 0, sct: 1, cin: 2}` | distinct hour per site |
| `freeipa_autopatch_reboot_oncalendar` | `""` | full override; bypasses the computation |
| `freeipa_autopatch_randomized_delay` | `20m` | jitter on every timer |

The per-site reboot offset keys off the `site` var (set once in
`group_vars/site_<code>.yml`). A site not present in the offset map falls back
to offset 0 — set `freeipa_autopatch_reboot_oncalendar` explicitly for it, or
add it to the map.
