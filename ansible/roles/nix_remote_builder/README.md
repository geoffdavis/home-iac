# nix_remote_builder

Turns a non-NixOS Linux host into an **ssh-ng nix remote build endpoint**
for the fleet: Determinate Nix, a dedicated protocol-only build account, the
fleet's pinned client keys, a kernel-enforced CPU/memory cap, and the sshd
`PerSourcePenalties` workaround that remote building on OpenSSH 9.8+
requires.

Today's only consumer is `amd-halo`. The NixOS builders (`nas-sdg`,
`nas-sct`, `torrey`, `tourmaline`) declare the same endpoint natively in the
**nix-personal** repo — see `hosts/tourmaline/builder.nix` and
`modules/builder-client-keys.nix` there. This role is the version of that
config for hosts nix cannot configure itself, and it is deliberately shaped
to converge on the *same* endpoint so one client key works everywhere.

**Scope: the endpoint only.** The client half — `nix.buildMachines` entries,
`speedFactor`, the `/etc/nix/builder_ed25519` credential each client
presents — lives in nix-personal (`modules/talos-builders.nix` is the
pattern for a non-NixOS builder). Nothing here touches it.

## What it does

1. **Installs Determinate Nix** via the pinned Determinate `nix-installer`
   (`install linux --init systemd --no-confirm`), guarded on
   `/nix/receipt.json` so a second run is a no-op. Set
   `nix_remote_builder_install_nix: false` to manage nix elsewhere.
2. **Creates the build account** — `nix-remote-builder`, a system user with
   home `/var/lib/nix-remote-builder` (0700) and a **real shell**, plus
   `loginctl enable-linger`.
3. **Writes `authorized_keys`** from `nix_remote_builder_client_keys`, each
   entry pinned `restrict,command="…nix-daemon --stdio"`. Managed as a whole
   file, so removing a key from the defaults removes it from the box.
4. **Adds `extra-trusted-users`** to `/etc/nix/nix.custom.conf`, plus
   `max-jobs`/`cores`.
5. **Caps the daemon** with a `nix-daemon.service` systemd drop-in
   (`CPUQuota`, `CPUWeight`, `IOWeight`, `MemoryHigh`).
6. **Disables the `noauth` sshd penalty class** via
   `/etc/ssh/sshd_config.d/10-nix-remote-builder.conf`.
7. **Verifies** that `trusted-users` and the CPU quota actually took effect
   — both fail *silently* otherwise.

## The five things that are easy to get wrong

### 1. Determinate Nix owns `/etc/nix/nix.conf`

Its header says `do not modify! this file will be replaced!`, and it means
it. That file `!include`s `/etc/nix/nix.custom.conf`, which is where our
settings go. The role manages a **marked block** inside it rather than
templating the whole file, because the installer seeds a header there too.

The include sits *after* nix.conf's own `max-jobs = auto`, and nix takes the
last assignment — so the block wins. Re-check that ordering after a
Determinate upgrade rather than assuming it.

`extra-trusted-users` (additive) is used rather than `trusted-users`
(absolute), so `root` keeps its trust without us restating a list we do not
own. Verified live: `nix config show` reports
`trusted-users = root nix-remote-builder`.

### 2. `trusted-users` is not optional, and fails silently

ssh-ng injects derivations and closures into the builder's store, which an
untrusted user may not do. With it missing, the client authenticates fine
and every build is then refused — which reads like a client-side problem.
The role asserts it after converging.

### 3. `PerSourcePenalties` will lock clients out

OpenSSH 9.8+ penalises a source IP that opens connections and closes them
without authenticating. That is *ordinary nix client behaviour*. This is not
hypothetical on this fleet — on `tourmaline` it locked `windansea` out
entirely:

```
srclimit_penalise: 100.92.221.141/32: activating ipv4 penalty of
  15.322 seconds for penalty: connections without attempting authentication
```

`amd-halo` runs OpenSSH 10.0p2 and shipped the default `noauth:1`.

The role writes `PerSourcePenalties noauth:0` — **not**
`PerSourcePenaltyExemptList`, which `nas-sdg` uses. The exempt list disables
*every* penalty class, `authfail` included, for a whole address range, so
anything on the overlay could brute-force freely. `noauth:0` disables
exactly the class nix trips and leaves `crash`/`authfail`/`invaliduser`/
`grace-exceeded` armed.

Support is detected by probing `sshd -T` for the keyword, not by parsing a
version string — vendor suffixes like `10.0p2 Debian-7+deb13u4` make version
comparison unreliable.

### 4. A real shell is required

`sshd` runs the forced command *through the login shell*. `/usr/sbin/nologin`
here makes every remote build fail at connect time. Same reason
`hosts/tourmaline/builder.nix` sets `shell = pkgs.bashInteractive`.

### 5. Builds land in `nix-daemon.service`'s cgroup, not the ssh session's

The forced command is `nix-daemon --stdio`, but run as an unprivileged user
that binary does **not** build anything: it proxies the worker protocol to
the real daemon on `/nix/var/nix/daemon-socket/socket`. So every remote build
executes under `nix-daemon.service`, and a drop-in on that unit is the one
place that catches all of them. Capping the ssh session scope would cap
nothing.

## Capping

`amd-halo` runs AI workloads between builds. Those workloads are
**GPU-resident** — the host side of them is a feeder, not a compute load —
so the requirement is a small *guaranteed* CPU slice rather than a large
reservation.

| Layer | Setting | Value |
| --- | --- | --- |
| systemd (**guarantee**) | `CPUQuota` | `3000%` — 30 of 32 threads |
| systemd | `CPUWeight` / `IOWeight` | `20` (below the default 100) |
| systemd | `MemoryHigh` | `48G` (soft: throttle + reclaim) |
| nix (**tuning**) | `max-jobs` | `8` |
| nix (**tuning**) | `cores` | `4` |

**Why both layers.** nix's own settings give an *average*; the cgroup gives
a *guarantee*. Two ways the nix half alone fails: a trusted client can send
its own build settings over the worker protocol, and a single derivation
whose build system ignores `NIX_BUILD_CORES` can saturate every thread by
itself. The kernel-enforced quota holds in both cases, which is why the role
asserts `CPUQuotaPerSecUSec != infinity` after reload — systemd accepts an
unsupported cgroup property silently and simply does nothing with it.

**Why `CPUQuota` and not `AllowedCPUs`.** A cpuset would hand the feeder
dedicated silicon, but it also stops builds from using an otherwise-idle
box, and with the AI work on the GPU there is no cache-thrash argument for
pinning. `nix_remote_builder_allowed_cpus` exists (default empty) if the
feeder ever turns out to need specific CPUs; on this CPU the SMT sibling of
core *N* is CPU *N* and CPU *N+16*, so a whole-core set looks like
`"8-15,24-31"`, never `"8-15"`.

**Why `MemoryHigh` and not `MemoryMax`.** `MemoryMax` OOM-kills, turning
memory pressure into failed builds. `MemoryHigh` throttles and reclaims.
This matters *more* here than on a discrete-GPU box: the Ryzen AI MAX+ 395's
iGPU has no VRAM of its own, so model weights live in the same system RAM a
`-j32` nixpkgs build would otherwise claim.

**Why `max-jobs 8` / `cores 4`.** 32 nominal build threads against a
30-thread quota — deliberately just over, so the quota stays saturated while
individual jobs sit in configure/link phases that do not parallelise.

## The "rex" platform

`amd-halo` runs *AMD Ryzen AI Developer Platform 1 ("rex")*. It is
Debian-derived (`ID_LIKE=debian`, `apt`, OpenSSH from Debian) but **not
Debian as far as Ansible is concerned**:

| Fact | Value |
| --- | --- |
| `ansible_distribution` | `AMD Ryzen AI Developer Platform` |
| `ansible_os_family` | `AMD Ryzen AI Developer Platform` ← **not `Debian`** |
| `ansible_distribution_release` | `rex` |
| `ansible_distribution_major_version` | `1` |
| `ansible_distribution_file_variety` | `NA` |
| `ansible_pkg_mgr` | `apt` ← correct |
| `ansible_service_mgr` | `systemd` |

So `when: ansible_os_family == "Debian"` is **false** here, and any map keyed
on a Debian codename (`bookworm`, `trixie`) misses on `rex`. The role gates
on `ansible_pkg_mgr`/`ansible_service_mgr` instead — Ansible derives those
independently and gets them right, and `ansible.builtin.apt` /
`ansible.builtin.package` work normally.

The kernel is a vendor build (`6.18.35+rex+2-amd64`); `systemd 257`,
cgroup v2 with the `cpuset`, `cpu`, `io` and `memory` controllers available.
Debian's ssh unit is `ssh.service` with `sshd.service` only as an alias.

## Variables

Everything is under the `nix_remote_builder_` prefix; see
`defaults/main.yml`, which carries the rationale for each value inline. The
ones most likely to need changing:

| Variable | Default | Purpose |
| --- | --- | --- |
| `nix_remote_builder_install_nix` | `true` | Install Determinate Nix (set `false` if managed elsewhere) |
| `nix_remote_builder_installer_version` | `3.22.3` | Pinned installer release |
| `nix_remote_builder_client_keys` | 6 fleet keys | Who may dispatch builds here |
| `nix_remote_builder_max_jobs` / `_cores` | `8` / `4` | nix parallelism |
| `nix_remote_builder_cpu_quota` | `3000%` | Kernel-enforced CPU ceiling |
| `nix_remote_builder_memory_high` | `48G` | Soft memory ceiling |
| `nix_remote_builder_allowed_cpus` | `""` | Optional cpuset (see above) |
| `nix_remote_builder_capping` | `true` | Whole capping drop-in on/off |
| `nix_remote_builder_sshd_penalties` | `true` | `PerSourcePenalties noauth:0` on/off |
| `nix_remote_builder_verify` | `true` | Post-converge assertions |

`nix_remote_builder_client_keys` must track nix-personal's
`modules/builder-client-keys.nix`. It currently carries **one extra** entry
that module does not: `nix-builder@nas-sdg`, because on this box the fleet
hub is a *client* rather than the builder.

## Usage

```sh
# amd-halo is not a NetBox-tagged device, so the static inventory is the path
task ansible:run-static -- playbooks/nix-remote-builder.yml

# dry run
task ansible:run-static -- playbooks/nix-remote-builder.yml --check --diff
```

Idempotent; safe to re-run.

## Verifying the endpoint

From a client, as root (the account that holds `/etc/nix/builder_ed25519`):

```sh
nix store ping --store \
  'ssh-ng://nix-remote-builder@172.29.30.23?ssh-key=/etc/nix/builder_ed25519'
```

`Trusted: 1` is the answer that matters — `Trusted: 0` means step 2 above
did not take, and builds will be refused even though the ping succeeded.

Then prove a derivation runs *there* rather than locally:

```sh
nix build --impure --no-link --print-out-paths \
  --store 'ssh-ng://nix-remote-builder@172.29.30.23?ssh-key=/etc/nix/builder_ed25519' \
  --expr 'derivation {
    name = "amd-halo-probe"; system = "x86_64-linux"; builder = "/bin/sh";
    args = ["-c" "{ hostname; nproc; echo NIX_BUILD_CORES=$NIX_BUILD_CORES; } > $out"];
  }'
```

Read the result back with `nix store cat --store …` — it should print
`amd-halo`, not the client's hostname.
