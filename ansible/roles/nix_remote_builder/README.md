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
7. **Sets up binary-cache push** to nas-sdg — generates the credential,
   pins the host key, installs the ssh alias and the `post-build-hook`.
   See [Binary-cache push](#binary-cache-push).
8. **Verifies** that `trusted-users`, the CPU quota and the `post-build-hook`
   took effect — all three fail *silently* otherwise — and that the
   cache-push alias is broken only in the expected not-yet-authorised way.

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

## Binary-cache push

Without this, closures built here never reach the fleet cache and every
other host rebuilds them — "faster builds, colder cache". The role is an
Ansible port of nix-common's `modules/cache-push.nix`, which is a
NixOS/darwin module and so cannot apply to this box; the *effect* is
reproduced, and that module's comments remain the record of why each number
is what it is. **Read it before changing any of them.**

A **file-based** cache, not nas-sdg's Harmonia cache: Harmonia serves
nas-sdg's live `/nix/store`, so anything pushed there is an unrooted store
path that `nix-collect-garbage` can reclaim. The file cache sits outside the
store.

Three pieces, all role-managed:

| Piece | Path |
| --- | --- |
| Credential (generated by the role) | `/etc/nix/nix-cache-push_ed25519` |
| ssh alias + pinned host key | `/etc/ssh/ssh_config.d/10-nix-cache-push.conf`, `/etc/nix/nix-cache-push.known_hosts` |
| Hook | `/etc/nix/cache-push-hook.sh`, wired via `post-build-hook` in `nix.custom.conf` |

### The credential is separate from the builder key, on purpose

`/etc/nix/nix-cache-push_ed25519`, not `/etc/nix/builder_ed25519` — the same
split (and the same path) nas-sct uses. A builder credential can inject
store paths into the receiving host; a cache credential only writes NAR
files. Conflating them widens both — see nix-personal's
`modules/builder-client-keys.nix`.

It is **generated by the role**, guarded on `creates:` so an existing key is
never regenerated — regenerating would silently invalidate nas-sdg's
authorised copy and turn every push into an auth failure. The role prints
the public half at the end of each run.

### `--kill-after` is load-bearing

Plain `timeout N` sends `SIGTERM` and then waits **forever**, so against a
child that ignores it the "hard bound" bounds nothing. nas-sdg's sibling
hook lacked it: on 2026-08-16 four of its pushes wedged in `futex_do_wait`,
shrugged off `SIGTERM`, and were still alive 4.4 hours later — each holding
a shared `/nix/var/nix/gc.lock`, which starved GC until the host hit 100%
disk and every deploy to it hung. This hook blocks the build and has the
same blast radius, so it gets the same escalation.

The wall-clock timeout is a **backstop, not the stall detector**, and must
sit above the other two bounds or it preempts them:

| Bound | Catches | ~ |
| --- | --- | --- |
| `ConnectTimeout 4` | unreachable host | 4s |
| `ServerAliveInterval 15` × `CountMax 3` | stalled connection | 45s |
| `timeout 600 --kill-after=60` | pathological hang | 600s / 660s |

An earlier 30s here was a *throughput gate* in disguise: whether a path
landed depended on its size against current link speed, so a 354 MiB path
squeaked through often enough that nobody investigated and failed often
enough never to persist.

### Failures are non-fatal but not silent

A broken cache must never fail a build, but the original `|| true` produced
no output and hid a real bug for months. Three distinct messages survive the
port, all greppable by the `cache-push:` prefix:

| Exit | Message |
| --- | --- |
| 124 | `cache-push: TIMEOUT after 600s; NOT cached: …` |
| 137 | `cache-push: HUNG, SIGKILLed after 660s (ignored SIGTERM); NOT cached: …` |
| other | `cache-push: FAILED (exit $rc); NOT cached: …` |

137 is named separately because it is the exact shape that wedged nas-sdg's
GC — worth being greppable rather than filed under a generic exit code.

### The ssh alias must be system-wide

`/etc/ssh/ssh_config.d/`, **not** `/root/.ssh/config`. `nix-daemon.service`
runs with an empty environment — `systemctl show nix-daemon.service -p
Environment` prints nothing — so the hook's ssh has no `HOME` and never
reads a user config *or* a user `known_hosts`. That second half is why the
role pins the host key in its own file: a plain `nix copy --to ssh-ng://…`
(unlike nix's remote-*build* path) injects no `known_hosts` of its own, so
without the pin the push dies at "failed to start SSH connection", which
reads like a network problem.

### Two deviations from `cache-push.nix`

1. **The destination address is a condition, not a literal.** When this role
   was written amd-halo was not a netbird peer — no netbird binary, and
   `nas-sdg.netbird.cloud` did not resolve there — so the overlay name would
   have failed closed on every push, and the LAN address `172.29.50.20` was
   used as a documented deviation. The `netbird_peer` role (which runs first
   in the play, precisely so this can see its result) now enrols the host,
   and the default reads:

   ```
   nas-sdg.netbird.cloud   if netbird_peer_enrolled
   172.29.50.20            otherwise
   ```

   Self-healing in the right direction: enrolment depends on a
   human-created setup key, so this keeps the working LAN path until
   enrolment actually succeeds, then moves to the overlay name on that same
   run — no follow-up edit, and no window where the hook points somewhere
   unreachable. The `| default(false)` lets this role stand alone. The
   host-key pin is keyed on the `HostKeyAlias` (`nix-builder-nas-sdg`), so
   neither address invalidates it.

   **The comment on that alias must stay one line per `#`.** A multi-line
   value emitted bare into `ssh_config` does not get ignored — ssh refuses
   to parse the whole file (`Bad configuration option`) and the ssh
   *client* breaks system-wide on this host, cache-push included. Caught
   live 2026-09-10 by this role's own alias probe; the template now
   prefixes every line individually.
2. **Absolute binary paths** (`/usr/bin/timeout`,
   `/nix/var/nix/profiles/default/bin/nix`) instead of nix store paths.
   `cache-push.nix` interpolates `${pkgs.coreutils}` and
   `${config.nix.package}`; there is no such reference available here, and
   the hook runs with an empty environment so nothing may rely on `PATH`.

### Fail-closed until authorised

The push is refused until this host's public key is added to nas-sdg's
`my.nixCache.fileCache.pushKeys` (nix-personal, `hosts/nas-sdg/nix.nix`) —
a different repo and a host this play does not target. **That is the correct
posture; do not loosen anything on nas-sdg to make it pass.** The role's
verification distinguishes that expected state from a genuinely broken
alias, and reports rather than fails.

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
| `nix_remote_builder_cache_push` | `true` | Whole cache-push feature on/off |
| `nix_remote_builder_cache_push_host` | `172.29.50.20` | nas-sdg's address (LAN — this box is not on the overlay) |
| `nix_remote_builder_cache_push_timeout` | `600` | Hook wall-clock backstop |
| `nix_remote_builder_cache_push_kill_after` | `60` | `SIGKILL` escalation — **do not remove** |
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
