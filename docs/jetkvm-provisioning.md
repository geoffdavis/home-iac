# Provisioning a JetKVM OOB console

Bring-up procedure for a new `jetkvm-<site>-<nn>` unit, from factory-fresh to
a monitored `class-oob-kvm` netbird peer with recovery media preloaded.

Written while provisioning `jetkvm-sdg-02` (2026-08-14), which was the fourth
unit and the first one done from a written procedure rather than from memory.
The three earlier units (`jetkvm-sdg-01` 2026-07-01, `jetkvm-cin-01` and
`jetkvm-sct-01` 2026-07-09) established the template this describes.

Day-2 maintenance is a separate thing — see
[`playbooks/jetkvm-netbird-update.yml`](../ansible/playbooks/jetkvm-netbird-update.yml).

## What you are working with

An armv7l busybox appliance. The constraints that shape everything below:

- **No python** → Ansible can only use `raw` against it; plays set `gather_facts: false`.
- **No sftp-server** → no `scp`, and no `copy`/`template`/`script` modules.
  File transfer is `cat`/`dd` over ssh — see [Transferring files](#transferring-files),
  which you should read before moving anything large onto one of these.
- **Two filesystems**: `/` is ~488 M and is **reflashed by every firmware
  update**; `/userdata` is 13 G and persists. Anything that must survive an
  update lives in `/userdata`.
- **Most settings are not on the HTTP API.** The device exposes only
  `/device/status`, `/device/setup`, `/auth/*`, `/metrics`, `/device`,
  `/storage/upload`, `/cloud/*`, `/webrtc/*` and a few others over plain HTTP
  (`web.go`). Hostname, Developer Mode, firmware update, and virtual media are
  **JSON-RPC over the WebRTC data channel** — browser only, not scriptable
  with `curl`. Plan for a human at a browser for those steps.
- **`/metrics` is served OUTSIDE the web auth.** Fine on the overlay and the
  mgmt VLAN; remember it when reasoning about destination-LAN exposure.

## Transferring files

`scp` does not work against these devices, and it fails in a way that is easy
to misread as success. Modern `scp` uses the SFTP protocol, and dropbear here
ships no server:

```text
sh: /usr/libexec/sftp-server: not found
scp: Connection closed
```

That is **exit 255, and nothing is copied.** Use a portable stream instead:

```sh
J=172.29.10.6
F="$HOME/nas-sdg-installer.iso"
set -o pipefail
timeout 3000 sh -c "cat '$F' | ssh -o ConnectTimeout=15 root@$J \
  'cat > /userdata/jetkvm/images/nas-sdg-installer.iso'"
RC=$?
echo "TRANSFER_RC=$RC"
```

> ⚠️ **Do not mask the exit code.** A trailing `echo`, or piping the command
> into `tail`/`head`, makes the shell report the *last* command's status — so a
> transfer that died at 255 reports "completed exit 0" and you carry on
> believing a file exists that does not. Set `-o pipefail`, capture `RC=$?`
> immediately after the command, and print `RC` as a separate statement. This
> has bitten this repo more than once; it is a reporting bug, not a transfer
> bug, and it is the more dangerous of the two because it is silent.

**Verify by size and checksum on the device, never by exit code alone:**

```sh
ssh root@$J 'ls -l /userdata/jetkvm/images/nas-sdg-installer.iso'
ssh root@$J 'sha256sum /userdata/jetkvm/images/nas-sdg-installer.iso'
```

> ⚠️ **There is no `stat` on this device** — busybox here is built without it
> (`sh: stat: not found`, rc 127; `busybox --list` has no `stat` applet).
> `strings` *is* present (`/usr/bin/strings`, a busybox applet) — but it is
> busybox `strings`, not GNU, so GNU-only flags fail and an over-narrow `-n`
> can return nothing, which reads like absence. Check `busybox --list` before
> concluding a tool is missing. The obvious progress check,
> `stat -c%s <file> || echo 0`, therefore reports **0 for a transfer that is
> running perfectly**, because the `|| echo 0` fallback swallows the missing
> binary. This has twice been misread as "the transfer never started". Use
> `ls -l`. Avoid `wc -c` too: it reads the whole file and will simply hang on a
> multi-GB ISO on this SoC.
>
> Same lesson as the exit-code trap above: a fallback that turns "command not
> found" into a plausible value is worse than a crash.

For a multi-GB file over the overlay, prefer the chunked `dd bs=4194304
seek=$i conv=notrunc` loop from `jetkvm-netbird-update.yml`: each chunk is
idempotent and retryable, so a tunnel flap repeats one 4 MiB chunk instead of
restarting from zero. A flat-out pipe saturates the SoC, starves the netbird
daemon, and drops the very tunnel carrying the transfer. On the LAN a single
stream is fine. Either way, clear any stale partial first — `conv=notrunc`
never truncates, so leftovers from an aborted run keep trailing bytes and fail
the checksum.

Watch progress from a second shell rather than trusting the stream to tell you
anything; it is silent until it finishes:

```sh
watch -n30 "ssh root@$J 'ls -l /userdata/jetkvm/images/nas-sdg-installer.iso'"
```

Expect roughly 4 MB/s over the mgmt VLAN — a 1.4 G ISO is about 6 minutes, and
the 4.1 G Talos image closer to 20. It is the SoC, not the network.

## Naming

`jetkvm-<site>-<nn>`, and the **device hostname, the netbird peer name, and
the DNS label must all be that same string**. `nas-maintenance.sh` in
nix-personal builds maintenance silences by matching the *site suffix*
(`.*sdg.*`), so a console whose name doesn't carry its site will keep paging
while its NAS is deliberately down.

## 0. Physical

- HDMI + the **data** leg of the USB-C Y-cable go to the NAS.
- The **power** leg goes to a UPS-backed charger, **never a NAS USB port** —
  a hard-off NAS must not kill the console you need to fix it with.
- The Y-cable legs are unlabeled and shipped swapped on at least one unit
  (`jetkvm-cin-01`, which read USB `Disconnected` until they were switched).
  **Tape-label both legs — DATA→NAS, PWR→charger — while you know which is which.**
- Give the unit a DHCP reservation on the Management VLAN (`172.29.10.0/24`)
  and confirm `jetkvm-<nn>.mgmt.home.geoffdavis.com` resolves. UniFi generates
  that record from the client name; `ansible/roles/unifi_network_dns_record`
  exists if you need to add one explicitly.

## 1. Firmware first

Settings → General → Update. Bring the unit to the same version as the rest of
the fleet (`jetkvm_build_info` in `/metrics` reports it, no auth needed):

```sh
curl -s http://<ip>/metrics | grep jetkvm_build_info
```

**Do this before installing netbird.** Firmware updates reflash `/`, which
destroys `/etc/init.d/S50netbird`. Updating first means you install the init
script once instead of restoring it afterwards.

## 2. Initial password

This is the one setup step that *is* scriptable, and doing it from the shell
is preferable because it lets you generate the password and file it in
1Password without it ever being typed:

```sh
python3 -c "import secrets,string; a=string.ascii_letters+string.digits; \
  open('pw.txt','w').write(''.join(secrets.choice(a) for _ in range(24)))"
python3 -c "import json; print(json.dumps({'localAuthMode':'password','password':open('pw.txt').read()}))" > setup.json
curl -s -X POST http://<ip>/device/setup -H 'Content-Type: application/json' --data-binary @setup.json
```

> ⚠️ **Verify the password is non-empty before you POST it.**
> `handleSetup` (`web.go:880`) assigns `config.LocalAuthMode = req.LocalAuthMode`
> *before* validating the password at line 883, and the empty-password path
> returns 400 without ever reaching `SaveConfig()` (line 917). The result is a
> device whose **in-memory** config says "password mode" with no hash: it
> answers `{"isSetup":true}`, returns 401 on everything, and refuses a second
> `/device/setup` with `"Device is already set up"`. Nothing was written to
> disk, so **a power-cycle fully clears it** — do not reach for the microSD/DFU
> factory reset. This is how the 2026-08-14 bring-up lost ten minutes: a
> `$(openssl rand ...)` substitution produced an empty string because `openssl`
> was not installed on the control node.

Use `noPassword` for nothing. The shipped units sit on other people's LANs,
and JetKVM has no local multi-user or operator accounts — it is a single
password or cloud adoption, and we do not adopt into JetKVM Cloud
(`cloud_token` stays empty). On-site helpers get physical hands and the
printed cheat sheet, not an account.

Verify, then file it:

```sh
curl -s -X POST http://<ip>/auth/login-local -H 'Content-Type: application/json' \
  -d "$(python3 -c "import json;print(json.dumps({'password':open('pw.txt').read()}))")" -c cookies.txt
curl -s -b cookies.txt http://<ip>/device   # {"authMode":"password", "loopbackOnly":false, ...}

op item create --category login --title "jetkvm-<site>-<nn>-web" --vault nas-overlay \
  --url "http://jetkvm-<nn>.mgmt.home.geoffdavis.com" "password=$(cat pw.txt)"
```

## 3. Hostname and Developer Mode (browser)

Both are WebRTC-RPC, so they need a browser session against `http://<ip>/`:

1. **Settings → Network → Hostname** → `jetkvm-<site>-<nn>`.
2. **Settings → Advanced → Developer Mode** → enable, and paste the
   `op-Personal` and `op-ansible` **public** keys. This is what populates
   `/userdata/dropbear/.ssh/authorized_keys` and starts dropbear on :22.

> **The Developer Mode toggle needs a genuine user event** — press Space on
> the focused checkbox. A programmatic checkbox set does not persist. This bit
> browser automation during the 2026-07-09 round.

Dev mode is key-only by design; the web password is never accepted for SSH.
The marker file is `/userdata/jetkvm/devmode.enable`, and because it and the
keys live in `/userdata`, **dev mode survives firmware updates**.

Confirm:

```sh
ssh root@<ip> 'cat /etc/hostname; ls /userdata'
```

## 4. netbird

Copy the working set from an existing console rather than fetching a release,
so the fleet stays on one version:

```sh
# on the reference unit
ssh root@<reference> 'ls -la /userdata/netbird/'
#   netbird (armv6)  cacert.pem  S50netbird  apply-update.sh  config.json
```

Transfer `netbird`, `cacert.pem`, `S50netbird` and `apply-update.sh` into
`/userdata/netbird/` on the new unit per [Transferring files](#transferring-files),
then install the init script:

```sh
ssh root@<new> 'cp /userdata/netbird/S50netbird /etc/init.d/S50netbird'
```

`S50netbird` does two JetKVM-specific things worth knowing: `modprobe tun`,
and `export SSL_CERT_FILE=/userdata/netbird/cacert.pem` because the rootfs
carries no CA bundle. Any manual `netbird` invocation needs that env var too.

Mint a **one-off setup key** with the `class-oob-kvm` auto-group:

- Token: **`Netbird Access Token - Claude`, vault `Automation`, field `password`**.
  (`op://nas-media/Netbird Ansible` 403s on key minting — do not use it.)
- 7-day expiry, ephemeral OFF.
- File the key as `netbird-setup-key-jetkvm-<site>-<nn>` (API_CREDENTIAL) in
  the `nas-overlay` vault.

`class-oob-kvm` is the **only** group the peer needs. Every ACL policy in this
tenant is written against `class-*`; `site-*` is used for scoping and setup
keys, never for access — a peer holding only a site group matches zero
policies and can reach nothing. (The ansible `site_<code>` group is a
different, unrelated axis; the console does belong there.)

Bring it up, then verify the peer registered under the exact expected name:

```sh
ssh root@<new> 'export SSL_CERT_FILE=/userdata/netbird/cacert.pem; \
  /userdata/netbird/netbird status --daemon-addr unix:///var/run/netbird.sock'
# Management: Connected / FQDN: jetkvm-<site>-<nn>.netbird.cloud
```

> If you ever re-enroll a unit, **delete the old peer in the dashboard first**.
> Re-enrolling over a live peer yields a `-1` suffix
> (`jetkvm-sdg-02-1.netbird.cloud`) and leaves the canonical DNS name attached
> to the dead peer.

**Reboot drill**: power-cycle and confirm netbird self-starts and the overlay
name answers SSH and HTTP inside about a minute. This is the whole point of
the init script; test it before you trust it.

## 5. Recovery media

Build the site's installer ISO in nix-personal and stage it into
`/userdata/jetkvm/images/` (that path survives firmware updates):

```sh
cd ~/src/nix/nix-personal
nix build .#nas-<site>-installer-iso
```

Then move it across per [Transferring files](#transferring-files) and confirm
the on-device checksum matches the build output. Do not skip the checksum: a
truncated ISO mounts happily as virtual media and fails halfway through an
install, at the worst possible moment.

```sh
sha256sum result/iso/*.iso
ssh root@<new> 'sha256sum /userdata/jetkvm/images/nas-<site>-installer.iso'
```

The full-reinstall path is then JetKVM Virtual Media + `nixos-anywhere` over
the overlay, with no on-site hands beyond a power cycle. Two traps:

- **Eject the virtual ISO before rebooting**, or the box boots the CD again.
- The **sdg** installer MAC-pins `bond0` to reproduce the DXP8800's LACP bond.
  Boot it only while the real `nas-sdg` is DOWN, or the two clash.

Known upstream quirks: BIOS may need a virtual replug to detect mounted media
(`jetkvm/kvm#561`), and mounted media can break the BIOS keyboard
(`jetkvm/kvm#560`).

## 6. Register it

Nothing about a console is auto-discovered. Four places:

| Where | What |
| --- | --- |
| `ansible/inventory.yml` | add to `oob_kvm.hosts` (`ansible_host: <name>.netbird.cloud`) **and** to `site_<code>.hosts` |
| `ansible/tests/test_inventory_oob_kvm.py` | add to `EXPECTED_CONSOLES` |
| nix-personal `hosts/nas-sdg/monitoring-hub.nix` | append to `oobKvms`, then `task check:nas-sdg` + `task deploy:nas-sdg` |
| personal-notes | `Home Network Topology.md` VLAN 10 + OOB table; peer counts in `Netbird Overlay.md` |

> **Add the scrape target only once the peer is reachable.** An unreachable
> target trips `MetricsFeedDown` (`alerting.nix`, `up{job!="node"} == 0` for
> 30m) and you page yourself.

Then confirm the inventory and connection settings actually work end to end:

```sh
task ansible:run-static -- playbooks/jetkvm-netbird-update.yml --limit jetkvm-<site>-<nn>
```

**Not `task ansible:run`.** That target forces the dynamic NetBox
inventory, which deliberately excludes JetKVMs (`netbox_inventory.yml`
scopes to `role: server`) — it would silently match zero hosts instead of
failing loudly. `ansible:run-static` routes through the static
`inventory.yml` (where `oob_kvm` actually lives) instead. Equivalent to
`cd ansible && uv run ansible-playbook playbooks/jetkvm-netbird-update.yml
--limit jetkvm-<site>-<nn>` (bare `ansible-playbook`, no `-i`, also
resolves to the static inventory via `ansible.cfg`'s default) — the Task
wrapper is preferred for the 1Password `op run` credential injection it
adds, matching how every other migrated playbook in this repo is run.

**Pin the version.** With no `-e netbird_version=`, the play resolves the
*latest* GitHub release and would upgrade the fleet as a side effect of what
you meant as a check. Pass the version the fleet is already on to get a true
no-op (`changed=0`).

Two first-run snags, both on the control node rather than the device:

- **Host key.** Ansible connects to `<name>.netbird.cloud`, so trusting the
  LAN IP earlier does not help — you get `Host key verification failed`
  (and, non-interactively, a confusing `ssh_askpass: exec(): No such file or
  directory`). Confirm the fingerprint matches the one already trusted for the
  LAN IP, then `ssh-keyscan -t ed25519 <name>.netbird.cloud >> ~/.ssh/known_hosts`.
- **The play must be able to find a POSIX shell.** It used to pin
  `executable: /bin/bash` for `set -o pipefail`; on a NixOS control node
  `/bin` contains only `/bin/sh`, so every run died at the checksum task. Now
  plain POSIX with an explicit hash comparison — see the task comment.

A clean no-op run means the host resolves, the key is accepted, `raw` works,
and the on-device version matches the fleet.

## If the target host runs a kiosk on its HDMI

Check this before declaring a console working. It is the one failure mode
where every visible signal says "fine".

`nas-sdg` drives a Grafana wallboard on the same HDMI port the JetKVM
captures (`my.kiosk`, cage + chromium on **tty1**). So the console shows a
dashboard, not a login prompt — and **`Ctrl+Alt+F2` does nothing**, because
cage gates VT switching behind `-s` (`allow_vt_switch`; cage `seat.c:269`,
`cage.c:301`, `cage.1.scd`: *"Allow VT switching"*) and the NixOS module
passed no such flag. Since the compositor holds DRM master, the kernel's own
VT hotkeys are inert too, so nothing anywhere acts on the chord.

Everything else looks healthy while this is broken: HDMI captures, the mouse
scrolls the dashboard, keypresses are demonstrably generated. Only the single
keystroke that matters in an emergency silently does nothing — and you find
out at the exact moment SSH is already gone.

**Diagnose by elimination.** From another machine:

```sh
ssh <host> 'sudo chvt 2; sudo fgconsole; systemctl list-units "getty@*" --all'
```

If `fgconsole` reports `2` and `getty@tty2.service` spawns, the VT machinery
is fine and the compositor is the one eating the chord. (`chvt 1` to put the
wallboard back.) Note this diagnostic needs SSH, which is exactly what you
will not have in the situation the console exists for — so run it now, not
later.

**Do not try to fix this by making cage switch VTs.** cage takes `-s`
("Allow VT switching") and it does let you switch *away* — but cage 0.3.0
does not survive the transition: it exits 133, its restarts fail while
another VT is foreground, and you come back to a blank panel. Upstream
[cage#284][c284] ("Switching between Sway and Cage VTYs behaves weird") is
open, so this is not a setting to tune around. Measured on nas-sdg
2026-08-14; the attempt is recorded here so nobody repeats it.

**The fix is to not run a browser kiosk on a port that is also a console.**
nas-sdg now runs TUI dashboards pinned to VTs (`my.consoleDashboard` in
nix-personal — wtfutil on tty1, btop on tty2, getty on tty3+). A TUI holds
no DRM master, so VT switching is an ordinary kernel operation that cannot
be swallowed by a compositor or crash one. `modules/kiosk.nix` remains
correct for genuine wall displays with no console duty (pacificbeach,
windowpi).

[c284]: https://github.com/cage-kiosk/cage/issues/284

**Add JetKVM macros regardless**, for a separate reason that survives the
above. `Ctrl+Alt+F2` typed into the *operator's* browser is grabbed by the
operator's own compositor (Hyprland on birdrock) before it ever reaches the
KVM. And the virtual keyboard **taps** keys rather than holding modifiers, so
it cannot compose the chord either ([jetkvm/kvm#211][k211],
[#401][k401]). Macros can — `KeyboardMacroStep` carries `Keys` and
`Modifiers` as separate fields, so modifiers are genuinely held:

**Install this exact set on every unit** (`jetkvm-sdg-02` and `jetkvm-sct-01`
carry it as of 2026-08-14; `jetkvm-cin-01` is pending — it is offline with
`nas-cin`):

```json
"keyboard_macros": [
  {"id": "vt1", "name": "F1 - VT1 (health dash)",
   "steps": [{"keys": ["F1"], "modifiers": ["ControlLeft", "AltLeft"], "delay": 50}],
   "sortOrder": 1},
  {"id": "vt2", "name": "F2 - VT2 (btop)",
   "steps": [{"keys": ["F2"], "modifiers": ["ControlLeft", "AltLeft"], "delay": 50}],
   "sortOrder": 2},
  {"id": "vt3", "name": "F3 - VT3 (LOGIN)",
   "steps": [{"keys": ["F3"], "modifiers": ["ControlLeft", "AltLeft"], "delay": 50}],
   "sortOrder": 3}
]
```

> [!warning] Name macros after the **VT**, never after what is currently on it
> The first set installed on `jetkvm-sdg-02` was labelled `Console (Ctrl+Alt+F2)`
> and `Wallboard (Ctrl+Alt+F1)`. Both went stale within hours when that host
> moved from a Grafana kiosk to `my.consoleDashboard`: "Wallboard" pointed at a
> TUI health dashboard, and — far worse — **"Console" pointed at btop while the
> actual login prompt had moved to tty3.** An operator reaching for "Console" in
> an emergency would have got a resource monitor.
>
> VT numbers are stable; what runs on them is not. `F3 - VT3 (LOGIN)` stays true
> on a host with console dashboards (tty1 health, tty2 btop, tty3+ getty) and on
> a host with none (every VT is a getty, so F3 is still a login). Include all
> three even where only one is currently interesting.

Key names follow the browser `KeyboardEvent.code` convention
(`ui/src/keyboardMappings.ts`). Limits: 25 macros, 10 steps each, 10 keys per
step, delay clamped to 50–2000 ms. Patch them into
`/userdata/kvm_config.json` and reboot, or add them in Settings → Macros.

[k211]: https://github.com/jetkvm/kvm/issues/211
[k401]: https://github.com/jetkvm/kvm/discussions/401

## Verification checklist

- [ ] `curl -s http://<ip>/device/status` → `{"isSetup":true}`; `/device` with
      cookie → `"authMode":"password"`
- [ ] `ssh root@<name>.netbird.cloud 'cat /etc/hostname'` → the expected name
- [ ] `netbird status` → `Management: Connected`, FQDN matches
- [ ] `curl -s http://<name>.netbird.cloud/metrics | grep jetkvm_build_info` →
      fleet version
- [ ] ISO sha256 on-device matches the build output
- [ ] Reboot drill passed
- [ ] Web console shows the NAS login prompt, and USB reads **Connected**
- [ ] **If the host runs a kiosk**: `Ctrl+Alt+F2` from a JetKVM *macro*
      actually reaches a TTY — not just "the screen shows something"
- [ ] `up{job="jetkvm"}` includes the new instance at `1`
- [ ] `--limit` play runs clean

## Gotchas index

| Symptom | Cause |
| --- | --- |
| `"Device is already set up"` on a fresh unit | empty-password POST dirtied in-memory config; power-cycle |
| Dev Mode toggle won't stick | needs a real key event (Space), not a programmatic click |
| `ping` fails but SSH/HTTP work | no ICMP in the `class-oob-kvm` policies, by design |
| Peer connects but reaches nothing | missing `class-oob-kvm`; `site-*` grants no access |
| `-1` suffix on the overlay name | re-enrolled without deleting the old peer first |
| netbird gone after a firmware update | `/` was reflashed; restore `S50netbird` from `/userdata` |
| Tunnel drops mid-transfer | flat-out pipe starves the SoC; chunk it |
| USB reads `Disconnected` | Y-cable power/data legs swapped |
| `sh: /usr/libexec/sftp-server: not found` / `scp: Connection closed` | no sftp-server; `scp` cannot work, use `cat \| ssh 'cat >'` |
| Transfer "succeeded" but the file is absent or short | exit code masked by a trailing `echo` or a pipe into `tail`; check size + sha256 on-device |
| Progress check reports 0 bytes on a healthy transfer | no `stat` on the device; `stat -c%s \|\| echo 0` masks rc 127. Use `ls -l` |
| Macro named for what's on the VT, not the VT | labels go stale when the host's layout changes; "Console" pointed at btop after nas-sdg moved to console dashboards. Name them `Fn - VTn` |
| A tool "seems missing" but is there | busybox applets are not GNU — a GNU-only flag or an empty match looks like absence. `busybox --list` is the authority. `strings` exists; `stat` genuinely does not |
| Play dies at the checksum task with `/bin/bash: No such file or directory` | control node is NixOS, which has only `/bin/sh`. Fixed — the task is POSIX now; don't reintroduce an `executable:` pin |
| `Host key verification failed` / `ssh_askpass: exec()` from the play | the overlay FQDN is untrusted even if the LAN IP is; compare fingerprints, then `ssh-keyscan` it |
| A "verification" run upgrades the fleet | the play defaults to the latest release; pass `-e netbird_version=<current>` |
| Console shows a dashboard, `Ctrl+Alt+Fn` does nothing | a Wayland kiosk holds DRM master and eats the chord. Don't add `cage -s` (it crashes on the switch, cage#284) — move that host to `my.consoleDashboard`. See [the kiosk section](#if-the-target-host-runs-a-kiosk-on-its-hdmi) |
| Panel blank after returning from a console visit | cage exited 133 on the VT switch; `chvt 1` + `systemctl restart cage-tty1`. Real fix is to stop using a browser kiosk on a console port |
| `Ctrl+Alt+Fn` typed in the browser never arrives | the operator's own compositor grabs it first; send it from a JetKVM macro instead |
| `wc -c` on an image hangs | it reads the whole file; the SoC is too slow. Use `ls -l` |
