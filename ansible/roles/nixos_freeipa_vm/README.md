# nixos_freeipa_vm

Provisions a Rocky Linux 10 libvirt/KVM VM on a **NixOS** host as the
carrier for a FreeIPA replica. Stops at "the VM is up, netbird-connected,
packages installed". The actual `ipa-replica-install` runs from a separate
playbook (`playbooks/freeipa-install.yml`) that targets the VM directly via
the `ipa_replicas` inventory group.

The role drives libvirt directly — it shells out to `virsh` / `qemu-img` /
`zfs` over SSH; the host's libvirtd/OVMF/zfs come from nix-personal's
[`modules/nas/virt.nix`](https://github.com/geoffdavis/nix-personal/blob/main/modules/nas/virt.nix).
Task flow: preflight → provision → wait_reachable.

## What this role does

1. **Preflight** — assert the target actually runs NixOS (guards the
   transitional dual-membership hosts in the `nas_nixos` group), assert
   the operator pinned `nixos_freeipa_vm_image_sha256`, assert libvirtd is
   active and `virsh`/`qemu-img` runnable, ensure the libvirt NAT network
   is active + autostarted, ensure the image-cache dataset exists and
   resolve its real ZFS mountpoint (no `/mnt/<pool>` assumption), and
   fetch the netbird setup key + operator SSH pubkey from 1Password.
2. **Provision** — probe `virsh domstate`; if the domain is absent:
   download the Rocky 10 GenericCloud qcow2 to the image-cache dir
   (sha256-verified, idempotent), render the cloud-init template
   (`templates/cloud-init-userdata.yaml.j2`), build the NoCloud seed ISO on
   the controller (`files/build_seed_iso.py`, pycdlib), copy it over,
   `zfs create` the
   `<pool>/vms` parent + sparse 30G zvol, `qemu-img convert` the image
   onto the zvol, `virsh define` a rendered domain XML, `virsh autostart`,
   `virsh start`. If the domain exists: start it if shut off, else no-op.
3. **Wait reachable** — poll DNS for the netbird FQDN → wait for SSH →
   wait for `cloud-init status --wait`; then eject the seed CDROM media
   **live** (`virsh change-media --eject --live --config` — no stop/start
   cycle) and delete the ISO. On failure, fetch `/var/log/cloud-init.log`
   to the controller.

Cloud-init inside the VM installs netbird + freeipa-server packages,
registers the netbird peer, patches `/etc/hosts` to map the FQDN to the
overlay IP, and scrubs the one-use setup key.

## Networking: NAT + overlay, no LAN bridge

The domain's NIC attaches to libvirt's stock `default` NAT network.
That's deliberate and sufficient: the VM is a netbird peer
(`ipa-<site>-replica`) and FreeIPA binds the **overlay** IP
(`--ip-address=<overlay>` in freeipa-install.yml; `/etc/hosts` maps the
FQDN to it), so every consumer — replication peers, IPA clients, the NAS
itself — reaches the replica over netbird, never over the LAN. NAT gives
the VM the outbound path it needs (dnf, netbird registration) with zero
host network surgery.

Bridging the VM onto the LAN (for overlay-less access) is a **deferred
bench task** — it needs hands on the box to validate the bridge without
losing remote access, and nothing requires it today.

## What this role does NOT do

- Install FreeIPA — that's `playbooks/freeipa-install.yml`'s job.
- Manage the host's libvirt/OVMF/zfs installation — that's nix-personal
  (`modules/nas/virt.nix`); preflight only asserts it's there.

## Variable namespacing

All inputs are `nixos_freeipa_vm_*`. The site-derived identity vars are set
once in [`group_vars/nas_nixos.yml`](../../group_vars/nas_nixos.yml),
derived from `site` / `inventory_hostname`.

## Required variables

| Var | Description | Example |
|---|---|---|
| `nixos_freeipa_vm_name` | VM/domain name (also zvol leaf name) | `ipa-cin` |
| `nixos_freeipa_vm_server_fqdn` | FreeIPA realm FQDN for this replica | `ipa-cin.ipa.geoffdavis.com` |
| `nixos_freeipa_vm_netbird_peer_name` | Netbird peer name | `ipa-cin-replica` |
| `nixos_freeipa_vm_netbird_setup_key_op_item` | 1P item name (vault: `nas-overlay`) | `freeipa-netbird-setup-key-nas-cin` |
| `nixos_freeipa_vm_ssh_pubkey_op_item` | 1P item with operator SSH pubkey | `ansible-ssh-key-2026-08-27` |
| `nixos_freeipa_vm_image_sha256` | SHA256 of the Rocky 10 qcow2 (forces pinning) | `28628abf...` |

All six are derived from `site` / `inventory_hostname` in
`group_vars/nas_nixos.yml`; you only set them by hand when deviating from
the fleet convention.

## Optional variables (defaults in `defaults/main.yml`)

| Var | Default | Notes |
|---|---|---|
| `nixos_freeipa_vm_image_url` | Rocky 10 GenericCloud x86_64 qcow2 URL | Override only for a local mirror |
| `nixos_freeipa_vm_image_cache_dataset` | `iso` | Relative to pool; directory = the dataset's ZFS mountpoint |
| `nixos_freeipa_vm_vcpus` | `2` | |
| `nixos_freeipa_vm_memory` | `4GB` | IPA-docs minimum; rendered as MiB in the domain XML |
| `nixos_freeipa_vm_disk_size` | `30GB` | Rocky + IPA + logs; passed to `zfs create -V` as bytes |
| `nixos_freeipa_vm_pool` | `nvme` | ZFS pool name |
| `nixos_freeipa_vm_libvirt_network` | `default` | Stock NAT network (see networking section) |
| `nixos_freeipa_vm_netbird_management_url` | `https://api.netbird.io` | |
| `nixos_freeipa_vm_op_vault` | `nas-overlay` | 1P vault for the role's secrets |
| `nixos_freeipa_vm_nic_mac` | `null` → deterministic | `00:a0:98:` + sha256(name)[:6] |
| `nixos_freeipa_vm_operator_debug_password` | `null` | Set from 1P per-host for a `virsh console` fallback |

## Usage

```yaml
# playbooks/nixos-freeipa-vm.yml
- hosts: nas_nixos
  roles:
    - role: nixos_freeipa_vm
```

Run per-site (always with `--limit` — the nas_nixos group may contain
transitional dual-membership hosts):

```bash
cd ansible && ansible-playbook -i inventory.yml playbooks/nixos-freeipa-vm.yml --limit nas-cin
```

After this role completes successfully, run the install playbook against
the resulting VM (see the playbook header for the full operator sequence,
including the netbird setup-key dashboard step that must happen first):

```bash
ansible-playbook -i inventory.yml playbooks/freeipa-install.yml --limit ipa-cin
ansible-playbook -i inventory.yml playbooks/freeipa-install.yml --limit ipa_bootstrap --tags mesh
```

## Controller-side dependency: pycdlib

The NoCloud seed ISO is built on the ansible controller with
`files/build_seed_iso.py` (pure-Python pycdlib, declared in the top-level
`pyproject.toml` `[dev]` group, available via `uv run ansible-playbook ...`).
Building controller-side avoids maintaining a nix-shell ISO toolchain on
the host.

**Use `uv run ansible-playbook ...` — a bare/nix-profile `ansible-playbook`
does NOT see pycdlib**, and the resulting failure is `no_log`-censored (the
ISO payload carries the netbird setup key), which makes it miserable to
diagnose — this bit the ipa-cin bring-up on 2026-07-06. If you must run
outside uv, export `PYTHONPATH` pointing at a site-packages containing
pycdlib (the nix-built ansible wrapper prepends its own interpreter dirs to
PATH, so PATH-based tricks alone may not reach the delegated `python3`
subprocess).
