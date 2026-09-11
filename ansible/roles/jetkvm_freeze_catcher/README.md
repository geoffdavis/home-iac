# jetkvm_freeze_catcher

Manage a resident "freeze catcher" on a JetKVM OOB console: a watcher that
detects the NAS behind it freezing and sends Magic SysRq from the console's
own emulated keyboard, so the freeze leaves evidence instead of vanishing.

> **`Alt+SysRq+C` hard-crashes the target.** This role is default-OFF on every
> console and only arms where explicitly enabled. Read [Safety](#safety)
> before enabling it anywhere.

## Why this exists

`nas-sdg` freezes with no evidence at all: the journal cuts mid-line, there
is no kernel output, `efi_pstore` is empty every time, and the IT87 hardware
watchdog resets the box about 120 seconds later. Ten freezes in the 24h to
2026-09-11.

The only way to get evidence is to send SysRq inside that ~120s window:

| Key | Effect |
| --- | --- |
| `Alt+SysRq+W` | blocked-task dump into the kernel ring buffer |
| `Alt+SysRq+C` | forced panic, so `kmsg_dump` writes the ring-buffer **tail** into `efi_pstore` |

Printing alone is useless — the ring buffer dies with the reset. `efi_pstore`
survives it, and shows up in `/sys/fs/pstore` after reboot.

Deliberately **not** SysRq-T: dumping every task floods the buffer and evicts
the blocked-task output from the tail, which is the part that survives.

### Why it runs on the console, not on a laptop

Four earlier versions ran on the owner's Mac. All four **detected real
freezes and every capture failed**, for one reason: the keystrokes travelled
over ssh and the 1Password SSH agent died overnight.

Running on the console removes that entire class of failure. `/dev/hidg0` is
local, so a capture needs no ssh, no agent, no laptop awake, and no overlay.

## The bug this role fixes

The hand-made predecessor **did not fire on a real freeze.** At 2026-09-11
18:14:31 nas-sdg froze with the catcher running and armed, and it logged
nothing and sent nothing for the whole ~2-minute window.

Everything was tested on the device (`jetkvm-sdg-02`, 2026-09-11) and the
script itself turned out to be **correct**:

| Suspect | Result |
| --- | --- |
| The probe | Correct in every silence shape. Banner 0s; TCP-accepted-but-silent 6s; no ARP reply 3s; refused 0s. |
| `ARMED` never set | Ruled out. nas-sdg had been up since **11:45**, six hours before the freeze, so the first probe armed it. |
| The loop / busybox `sh` semantics | Ruled out. The production loop, **verbatim**, was run against a target silenced on demand: it armed, counted 4 failures and reached the fire branch in 50 seconds (silenced 19:10:13 → fired 19:11:03). |
| The launcher | Ruled out. `setsid` detaches correctly (`sid == pgrp == pid`, reparented to init), the daemon survives the ssh session closing, and `$!` records the right pid. |
| OOM | Ruled out. 136 MB available of 203 MB, no OOM kills in `dmesg`. (Load average 9.2 is a red herring — nine permanently-D-state video kernel threads.) |
| Editing the script in place | Ruled out. `sed -i` renames, so the running shell keeps its old fd. |

That leaves the control flow itself as the evidence. **While armed, the old
script had exactly two code paths that logged nothing**: the target answering,
and the unarmed `continue`. Every failure path logged — `NETWORK?` on a silent
witness, `FREEZE` on the fourth failure. Since arming is proven, a completely
empty log across an armed 2-minute freeze is only possible if the probe kept
returning "alive" or **the process was not running**. And by the freeze's own
documented physics — the kernel keeps servicing interrupts while userspace is
dead, which is why `nc -z` succeeds on a dead box — sshd could not have been
writing a banner, so the probe must have failed, so `FREEZE` must have been
logged. It wasn't.

**Root cause: the catcher was not running when the freeze came, and the
design made that indistinguishable from working.** A watcher that is silent
when healthy, silent when unarmed, and silent when dead cannot be trusted
when it is quiet — and that is exactly why the failure was unresolvable after
the fact. A catcher that looks armed and cannot fire is worse than none,
because it manufactures false confidence.

### What changed

1. **Heartbeat logging.** Every branch logs, and a periodic heartbeat proves
   liveness while healthy (`armed=1 ok_polls=N target=... ALIVE`). Silence now
   means something. This is the actual fix — it converts the next missed
   capture from a mystery into data.
2. **Supervision.** `supervise.sh` restarts the catcher if it ever exits and
   logs that it did. The proven failure mode was total and silent; now it is
   neither. (crond is not running on these devices and `/etc` is reflashed by
   firmware updates, so the supervisor lives in `/userdata` beside the payload.)
3. **A startup self-test that proves the capture path.** The catcher writes an
   all-zeros HID report — "no keys pressed", a genuine no-op on the target —
   and logs the result. The role fails the run if it reports `SELFTEST FAILED`.
   You now find out that a console cannot fire at deploy time, not during the
   one window that matters.
4. **The HID write no longer lies.** The old `printf "$R" >"$HID" 2>/dev/null`
   then logged "sent" unconditionally. Measured on-device: writing to a
   nonexistent gadget (`/dev/hidg9`) returns **rc=0**, so the old script would
   report keystrokes it never delivered. Stderr is now captured and checked.
5. **The unarmed branch logs.** It was one of the two silent paths.
6. **A probe classification that will resolve this if it recurs.** The log now
   distinguishes `SILENT_ACCEPTED` (TCP accepted, nothing written — the freeze
   shape) from `SILENT_NOCONN` (could not connect at all), by elapsed time,
   since busybox `nc` gives no usable exit status through the pipeline.
7. **A trustworthy pidfile.** `status` checks `/proc/<pid>/cmdline`, not just
   `kill -0`, so a recycled pid cannot make `status` lie or make `stop` kill a
   stranger.

## Safety

- **Default disabled, everywhere.** `jetkvm_freeze_catcher_enabled: false`.
- **Disabled means disarmed, not ignored.** On a console where it is not
  enabled the role removes the init script and kills any running catcher, so a
  console cannot keep an armed catcher it is no longer supposed to have —
  including after a firmware reflash and reinstall.
- **Witness guard.** It fires only when the target fails N consecutive probes
  *while an independent witness still answers*. Both silent = network fault =
  do not fire. Panicking a healthy hub over a switch blip is far worse than
  missing one capture.
- **Arm-after-healthy.** It never fires at a box it has not seen alive.
- **Addresses must be LAN IPv4 literals**, enforced by an assert. A hostname
  would silently never resolve, producing a catcher that can never arm.
- **`jetkvm_freeze_catcher_dry_run: true`** detects and logs exactly as normal
  but never writes to the HID. Commission new consoles this way.

## Probe design

The probe reads the **SSH banner**. Not ping, not a TCP connect:

- **ping** is filtered over netbird on this fleet — false alarms *and* misses.
- **A TCP connect is actively wrong.** The handshake is done by the *kernel*,
  which in these freezes keeps servicing interrupts for up to a minute after
  userspace dies, so `nc -z` reports success on a dead box. That mistake cost
  a real capture on 2026-09-11 02:35.
- **`SSH-2.0-...` can only be written by sshd**, so receiving it proves
  *userspace* is alive.

### Addressing: LAN-direct, never netbird

**Each console probes its NAS over the LAN, never over the overlay.** This is
the role's rule, not an artifact of one host:

1. **Netbird names do not resolve from these devices at all.** Measured
   2026-09-11: `nas-sdg.netbird.cloud` times out from jetkvm-sdg-02 while
   `172.29.50.20` answers instantly; `nas-sct.netbird.cloud` returns NXDOMAIN
   from jetkvm-sct-01 while `172.29.41.150` answers. The overlay is not merely
   slower here, it is non-functional for this purpose.
2. **Independence is the point.** The catcher must keep working when the
   overlay is down. A freeze that correlates with a netbird problem is exactly
   when you least want the watcher blinded, and a watcher that fails under the
   same conditions as its target is not a watcher.
3. **Shortest path**, so the detection window is not eaten by overlay latency
   during the ~120s before the watchdog fires.

Per-console addressing lives in `host_vars/`, because the consoles are not on
one segment — jetkvm-sct-01 shares nas-sct's `/24`, while jetkvm-sdg-02 is on
the Management VLAN and reaches nas-sdg across the UDM.

| Console | Target | Witness | Armed? |
| --- | --- | --- | --- |
| `jetkvm-sdg-02` | `172.29.50.20` (nas-sdg) | `172.29.50.1` | **yes** |
| `jetkvm-sct-01` | `172.29.41.150` (nas-sct) | `172.29.41.1` | no — recorded only |
| `jetkvm-sdg-01` | — | — | no (roaming rack unit) |
| `jetkvm-cin-01` | unknown | unknown | no — site offline, deliberately unconfigured |

For the witness, prefer the shared segment's **gateway**: always up, different
hardware from the target, and on the path the probe already uses. Verify it
actually answers on tcp/22 from the console before committing it.

## Persistence split

`/userdata` survives firmware updates; `/` is reflashed by every one of them.

- `/userdata/freeze-catcher/catcher.sh` — the payload, persists
- `/userdata/freeze-catcher/supervise.sh` — the supervisor, persists
- `/userdata/freeze-catcher/catcher.log` — the log, persists
- `/etc/init.d/S60freeze-catcher` — the launcher, **does not persist**

This mirrors `S50netbird`, whose binary lives at `/userdata/netbird/netbird`.
The role reinstalls the init script every run, which is what makes a console
recover its catcher after a firmware update instead of quietly losing it.

## Usage

```sh
task ansible:run -- playbooks/jetkvm-freeze-catcher.yml
task ansible:run -- playbooks/jetkvm-freeze-catcher.yml --limit jetkvm-sdg-02
task ansible:run -- playbooks/jetkvm-freeze-catcher.yml --check   # real drift report, writes nothing
```

Enable a console in `host_vars/<console>.yml`:

```yaml
jetkvm_freeze_catcher_enabled: true
jetkvm_freeze_catcher_target: 172.29.50.20
jetkvm_freeze_catcher_target_name: nas-sdg
jetkvm_freeze_catcher_witness: 172.29.50.1
```

## Operating it

```sh
ssh root@jetkvm-sdg-02.netbird.cloud
/etc/init.d/S60freeze-catcher status
tail -f /userdata/freeze-catcher/catcher.log
```

A healthy log looks like this — note that it says so out loud:

```
... catcher started: target=172.29.50.20:22 witness=172.29.50.1:22 hid=/dev/hidg0 dry_run=0 fails_to_fire=4
... SELFTEST OK: /dev/hidg0 accepted an empty key-release report; the capture path works
... ARMED — 172.29.50.20 seen healthy; the catcher will fire if it goes silent from here
... heartbeat — armed=1 ok_polls=20 target=172.29.50.20 ALIVE (0s)
```

After a capture, the evidence is on the **target**, not the console:

```sh
ssh nas-sdg 'sudo ls -la /sys/fs/pstore/'
```

## Timing

With the defaults a freeze is confirmed ~45–50s after the first failed probe
— measured end-to-end on jetkvm-sdg-02, 2026-09-11: target silenced at
19:10:13, fire branch reached at 19:11:03. That leaves ~70s of margin inside
nas-sdg's ~120s watchdog window. Raising `consecutive_fails` or the poll
intervals eats directly into that margin.

## Testing it without crashing anything

Never test by firing SysRq-C at a real host. Two safe methods, both used
while developing this role:

- **`jetkvm_freeze_catcher_dry_run: true`** — full detection, logs
  `DRY RUN — would send ...`, writes nothing to the HID.
- **Point a copy at a target you can silence.** `1.1.1.1:22` accepts TCP and
  never sends a banner, which is exactly the freeze shape. Beware
  `127.0.0.1`/`127.0.0.2` as a stand-in: the console's own dropbear listens on
  `0.0.0.0:22`, so *any* `127.x` address answers with a real SSH banner and the
  test silently proves nothing. (That cost two invalid runs before it was
  caught with `netstat`.)
