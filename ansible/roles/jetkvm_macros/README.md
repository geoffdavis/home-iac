# jetkvm_macros

Reproducible management of the `keyboard_macros` set in a JetKVM OOB
console's `/userdata/kvm_config.json`. Merges a declared set by `id`,
backs the file up first, and verifies what landed.

Driven by [`playbooks/jetkvm-macros.yml`](../../playbooks/jetkvm-macros.yml).

## Motivation

Macros are not a convenience on these devices — they are **the only way to
send a chord at all**:

- The JetKVM virtual keyboard *taps* keys and does not hold modifiers, so
  it physically cannot compose `Ctrl+Alt+F12` or `Alt+SysRq+W`
  ([jetkvm/kvm#211][k211], [#401][k401]).
- Typing the chord into the operator's own browser doesn't work either —
  the operator's compositor (Hyprland on birdrock) grabs it before it ever
  reaches the KVM.
- `KeyboardMacroStep` carries `Keys` and `Modifiers` as separate fields, so
  only a macro genuinely holds a modifier down.

And `/` is reflashed by every firmware update. `/userdata` survives, so the
macros themselves persist — but a hand-installed set is still only as
durable as whoever remembers to reinstall it on the next unit. That is what
this role is for.

[k211]: https://github.com/jetkvm/kvm/issues/211
[k401]: https://github.com/jetkvm/kvm/discussions/401

## Naming rule

**Name a macro after the VT number or the SysRq letter, never after what
currently runs there.** The first set installed on `jetkvm-sdg-02` was
labelled `Console (Ctrl+Alt+F2)`; when that host moved from a Grafana kiosk
to `my.consoleDashboard`, "Console" started pointing at **btop** while the
actual login prompt had moved to tty3. An operator reaching for "Console"
in an emergency would have got a resource monitor. VT numbers are stable;
what runs on them is not.

## Why SysRq is one step, not two

This is the load-bearing detail in `defaults/main.yml`, and it was settled
empirically, not by reading docs.

Linux needs **Alt held → SysRq pressed → command key pressed**, in that
order, with Alt still down. Two shapes could plausibly express that:

| Shape | What it looks like |
| --- | --- |
| **one step** | `keys: [PrintScreen, KeyW]`, `modifiers: [AltLeft]` |
| two steps | step 1 `[PrintScreen]`, step 2 `[KeyW]`, both with `AltLeft` |

**The one-step shape is the one that works.** Both were fired at
`jetkvm-sdg-02` (the console bolted to `nas-sdg`, which already runs
`kernel.sysrq=1`) and the result read off the NAS's own kernel log:

```text
2026-09-10 15:23:29  one-step   → sysrq: Show Blocked State     ✓
2026-09-10 15:23:45  two-step   → (nothing in the kernel log)   ✗
2026-09-10 15:24:19  one-step   → sysrq: Show Blocked State     ✓  (reproduced)
```

A separate one-step `SysRq T` run produced a full task dump plus
`Showing busy workqueues and worker pools` — and a
`/dev/kmsg buffer overrun, some messages lost` from journald, which is why
`journalctl -k` can *lose the `sysrq:` header line* on a large dump. Don't
read that as "it didn't fire"; check `dmesg` for the dump body too.

The firmware source says why, and the two agree:

- Within one step, `useKeyboard.ts` builds a **single** HID report —
  `{ keys: keyValues, modifier: modifierMask }` — and `KeyboardReport()`
  writes it as `[modifier, 0x00, key0, key1, ...]`, preserving array order.
  The kernel's `hid_input_field()` then emits presses in array-index order,
  so `PrintScreen` really does arrive before `KeyW`, with Alt already down.
  That is exactly the sequence `sysrq_handle_keypress()` wants.
- **Between** steps the firmware pushes `MACRO_RESET_KEYBOARD_STATE` — an
  all-zero report — so **modifiers do not persist across steps**. In the
  two-step shape Alt is released before the command key is sent, which
  clears `sysrq->active`, and the kernel sees nothing but a stray `Alt+W`.

So: any chord that needs one key held while another is pressed must be
**one step**. Put the held key first in the `keys` array.

## Idempotency and the merge

The declared set is merged **by `id`** into whatever the console already
carries. A macro whose id this repo does not declare is kept verbatim — a
unit may carry macros nobody here knows about, and this role will not eat
them. Merged macros are appended after the foreign ones; array position is
cosmetic because the web UI sorts by `sortOrder` before rendering.

Drift is decided by comparing **parsed** macro lists, never file bytes: the
role re-serializes the whole config and Ansible's `to_nice_json` will never
agree byte-for-byte with Go's `json.Encoder`, so a byte comparison would
report a change on every run.

## Safety

`kvm_config.json` is the device's **whole** config — password hash, network,
USB, EDID — not a macro file. Corrupting it on a remote console is how you
lose the recovery path you keep the console for. So:

1. The declared set is validated on the control node first: unique ids,
   step and key counts, delay range, and every key/modifier name checked
   against the firmware's own tables (`vars/main.yml`). An unknown key name
   is *silently dropped* by the UI's `.filter(Boolean)`, producing a macro
   that appears installed and sends nothing — the single worst outcome, so
   it fails here instead.
2. The merged config is rendered to a 0600 control-node temp file, read
   **back off disk**, re-parsed, and checked to still carry every top-level
   key the device had. Only then does anything move.
3. The device's current config is copied into
   `/userdata/kvm-config-backups/kvm_config.json.<stamp>` (last 10 kept)
   **before** the write. Deliberately not `<config>.bak` — the firmware's
   own `SaveBackupConfig()` writes that path during an OTA.
4. Transfer is `cat`-over-ssh (there is no sftp-server, so `copy`/`template`
   cannot work) into `<config>.ansible-new`, verified by `sha256sum` on the
   device against the control node's checksum, and only then `mv`'d into
   place. Never trust the exit code alone; a stream that dies mid-transfer
   can still look like success.
5. After the reboot the config is re-read and the macro set asserted.

The whole config, including its `hashed_password` and `local_auth_token`,
does transit the control node to be re-serialized — unavoidable without
`jq`/python on an armv7l busybox device. It is held in a 0600 temp file
that is removed in an `always:` block, and the control node already holds
the SSH key that owns the device, so this is not an escalation. Tasks that
carry the config are `no_log`.

## Applying: a reboot is required

`jetkvm_app` calls `LoadConfig()` exactly once, guarded by
`if config != nil { return }`, and exposes no reload RPC or SIGHUP path
(`config.go`). Its supervisor (`cmd/main.go`) does **not** respawn a killed
child, so "just restart the app" would leave the console dead. Rebooting
the console is the only supported way to make a written config take effect;
`serial: 1` keeps it to one console at a time. Rebooting the JetKVM does
not touch the NAS behind it — the USB gadget simply re-enumerates.

One live race worth knowing: between the write and the reboot, any settings
change made in the console's web UI calls `SaveConfig()`, which serializes
the app's **in-memory** config and would silently drop the freshly written
macros. Don't drive the web UI during a run.

Set `jetkvm_macros_reboot=false` to stage the config without applying it.

## `wait_for_connection` does not work on this device class

Waiting for the console to come back after the reboot is done by polling
plain `ssh` from the control node, not with `wait_for_connection`. That
module looks like the right tool and is not: it proves the connection by
running the **`ping` module**, which needs a python interpreter on the
target. These devices have none —

```console
$ ansible -i inventory.yml jetkvm-sdg-02 -m ping
"module_stderr": "/bin/sh: /usr/bin/python3: not found\n"
"msg": "The module interpreter '/usr/bin/python3' was not found.", "rc": 127
```

— so it can never succeed here. It burns its entire timeout and then fails,
on a device that was answering SSH the whole time. Raising the timeout does
not help; it just makes the failure take longer. (Confirmed live
2026-09-10, ansible-core 2.21.1.)

`until`/`retries` on a `raw` task is not a substitute either: an
`AnsibleConnectionFailure` returns immediately as *unreachable* without
consuming a retry, which is exactly what a rebooting host produces.

## Verification

The role does not trust "the bytes are on disk". `LoadConfig()` silently
falls back to the built-in **defaults** if `json.Unmarshal` fails, so a
corrupted config leaves a console that boots, answers SSH, has our file
sitting right there — and runs none of it. So after the reboot the role
asks the firmware directly, via the unauthenticated `/metrics` endpoint:

```text
jetkvm_config_last_reload_successful 1
jetkvm_config_last_reload_success_timestamp_seconds <epoch>
```

The timestamp is compared against its own **pre-reboot** value rather than
against the control node's clock — free of skew assumptions between a
laptop, a CI runner and an armv7l SoC, and it also catches the case where
the reboot never actually happened.

## Variables

See `defaults/main.yml` (the managed set and the write knobs) and
`vars/main.yml` (firmware-derived limits and the key/modifier allowlists,
validated against firmware 0.5.8 / rev `df5dbea`).

## Related

- [`playbooks/jetkvm-netbird-update.yml`](../../playbooks/jetkvm-netbird-update.yml)
  — the other day-2 play for this device class; source of the cat-over-ssh,
  checksum-verify and detached-restart patterns reused here.
- `group_vars/oob_kvm.yml` — connection settings and why host keys are
  deliberately unpinned.
- personal-notes: *Provision a JetKVM OOB Console* — bring-up procedure.
