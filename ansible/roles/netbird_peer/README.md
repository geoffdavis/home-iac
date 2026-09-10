# netbird_peer

Enrols a Debian-family host in the netbird overlay: pinned `.deb`, a
one-off setup key read from 1Password, enrolment detached from the ssh
session, and a post-check that the host's **LAN** path still works.

Today's only consumer is `amd-halo`. The NixOS fleet hosts configure
netbird declaratively in **nix-personal** (`modules/netbird.nix`,
`hosts/*/network/netbird.nix`); this role is for hosts nix cannot
configure.

## Why amd-halo is on the overlay

Before enrolment it was reachable only from the LAN, and
`nas-sdg.netbird.cloud` did not resolve there — which forced the
`nix_remote_builder` role's cache-push destination onto the LAN address
`172.29.50.20` as a special case. Enrolling removes the special case and
gives the box the same overlay identity as every other fleet host.

## Group choice: `class-builder`

netbird has no VLANs; its equivalent is **groups**, with policies between
them, and **there is no in-repo source of truth — the control plane is
dashboard-only.** Group membership is set by the *setup key's auto-groups*,
so choosing the group and creating the key are the same human act.

`class-builder` is the fit. Verified against the live netbird API on
2026-09-10 (not inferred from the topology note, which is stale on both
counts below):

| Policy | Source → destination | Ports | Gives amd-halo |
| --- | --- | --- | --- |
| `nas-to-builder-ssh` | `class-nas` → `class-builder` | tcp 22 | **inbound**: nas-sdg dispatching remote builds here |
| `builder-to-hub-ssh` | `class-builder` → `class-nas-hub` | tcp 22 | **outbound**: the cache-push hook reaching nas-sdg |

Those two are exactly this host's two needs, in the two directions it
needs them. Existing members are `tourmaline` and `torrey` — the fleet's
other build clients — and tourmaline sits on the same VLAN 30
(`172.29.30.0/24`) as amd-halo, which is useful evidence that a
`class-builder` peer on this subnet does not have its LAN path captured by
overlay routes.

Plus `site-sdg`, the per-site rollup every other San Diego peer carries;
the enrolment keys for tourmaline/torrey/windowpi/pacificbeach are all
shaped that way.

### Two places the topology note is out of date

Worth correcting there rather than restating here, per that note's own
convention:

1. It lists `class-builder` as **"torrey only"**. The live API shows
   **tourmaline and torrey**. The note's own line "Add tourmaline to
   `class-builder` only if it ever gains `my.cachePush`" appears to have
   happened without the note being updated.
2. It does not mention **`nas-to-builder-ssh`** (`class-nas` →
   `class-builder`, tcp 22) at all. That policy is the entire reason
   `class-builder` works as a *destination* here, so its absence from the
   note would lead a reader to conclude — as the note's tables do — that
   `class-builder` is source-only.

### The gap this does not close

There is **no `class-personal` → `class-builder` policy.** birdrock,
windansea, the windansea CI runner and slurricane all hold client keys in
amd-halo's `authorized_keys`, but over the overlay they cannot reach it on
tcp/22. They keep working over the LAN.

This is the owner's call, and it is the same shape as the two decisions the
topology note already records (`class-builder`'s own creation, and
`hub-to-appliance-ssh`): add a **new, narrow** policy rather than widening
`personal-to-appliance`, which would open tcp/22 on three appliances that
have no business accepting it.

```
personal-to-builder-ssh   class-personal -> class-builder   tcp 22
```

Remember the note's warning when checking: **a netbird denial is
indistinguishable from a dead host**, and a policy PUT echoing two rules
stores one — verify with a fresh GET.

## The setup key is a prerequisite, not a task

**Deliberately not automated.** Creating a setup key mints a credential, and
its auto-groups decide the host's ACLs — neither should happen as a side
effect of a play. The role fails with the exact steps if the key is absent.

Missing key is **non-fatal by default** (`netbird_peer_required: false`).
This role shares a play with `nix_remote_builder`, which keeps a box that is
taking real fleet builds converged; aborting over an absent credential would
stop that work for an enhancement whose absence costs nothing at runtime —
cache-push simply stays on the LAN address, which works. The prerequisite is
announced loudly on every run instead. Set `netbird_peer_required: true`
once enrolment is meant to be a settled fact.

There is **no valid setup key in the netbird account** as of 2026-09-10 —
every existing key is expired or fully used. So for a first enrolment the
owner must:

1. netbird console → Setup Keys → Create Setup Key
   - name: `amd-halo`
   - type: **one-off**
   - auto-groups: **`class-builder`**, **`site-sdg`**
2. Store it in 1Password — vault **`nas-overlay`**, item
   **`netbird-setup-key-amd-halo`**, field `password`.
3. Re-run the play.

The item name follows the convention in `group_vars/nas_nixos.yml`
(`nixos_freeipa_vm_netbird_setup_key_op_item:
"freeipa-netbird-setup-key-{{ inventory_hostname }}"`) with the role-specific
prefix dropped. `nas-overlay` is the vault the CI runner's 1Password Connect
is scoped to, so a key there works interactively *and* from CI.

**The key is consumed by first use.** It is a bootstrap credential, not a
standing one — which is fine, because the role only consults it when the
host is not already registered. A converged host needs no 1Password access
at all, which is what keeps a second run a clean no-op.

## Design notes

**Pinned `.deb`, not netbird's apt repo.** An apt repo would drift this
host's version on any unrelated `apt upgrade`, silently undoing the pin. The
version tracks the fleet (`0.77.1`, read off nas-sdg) — the overlay is a
distributed system and a peer several versions from its neighbours is a
debugging problem nobody wants. Integrity is the published `checksums.txt`
fed to `get_url`'s native `checksum:`; the role fails loudly if the expected
line is missing rather than handing `get_url` an empty checksum, which it
would treat as "no verification".

**Enrolment runs detached** (`systemd-run --collect --wait`). `netbird up`
brings up `wt0` and installs overlay routes; if that ever disturbed the LAN
path the play arrives over, an inline command would be killed halfway and
leave the host half-enrolled — the worst outcome. Detached, enrolment
completes either way.

**The LAN check is the point of the verification block.** The failure this
role most needs to catch is netbird capturing the LAN prefix the host sits
on, cutting the path that this play, the cache-push LAN fallback and
LAN-side ssh all depend on. It is checked **from the control node**, so it
tests the real path rather than the host's opinion of it.

**`wait_for_connection` needs python on the target.** It runs the `ping`
*module*, so it is not a pure transport check. Fine here (`/usr/bin/python3.13`),
but `playbooks/jetkvm-netbird-update.yml` carries a comment claiming the
opposite, and that comment is wrong — on those python-less JetKVMs the task
can never succeed, which is the likely cause of the 2026-08-28 timeouts
documented in that file (raised 120→180→300→600s, with "every device had
actually already come back"). Do not copy that comment.

## Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `netbird_peer_version` | `0.77.1` | Pinned release, tracks the fleet |
| `netbird_peer_hostname` | `{{ inventory_hostname }}` | Peer name → `<name>.netbird.cloud` |
| `netbird_peer_setup_key_op_item` | `netbird-setup-key-{{ inventory_hostname }}` | 1Password item name |
| `netbird_peer_op_vault` | `nas-overlay` | 1Password vault |
| `netbird_peer_expected_groups` | `[class-builder, site-sdg]` | Documentation + the failure message; **not** enforced |
| `netbird_peer_required` | `false` | Make a missing setup key fatal |
| `netbird_peer_enrol_detached` | `true` | Run `netbird up` via `systemd-run` |
| `netbird_peer_verify` | `true` | Post-checks incl. the LAN-path regression check |

## Role output

Publishes two **public** facts (not `_`-prefixed — later roles in the play
consume them):

| Fact | Meaning |
| --- | --- |
| `netbird_peer_enrolled` | bool; the host is a peer with a live management connection |
| `netbird_peer_fqdn` | e.g. `amd-halo.netbird.cloud`, or `''` |

`nix_remote_builder` keys its cache-push destination off
`netbird_peer_enrolled`, choosing nas-sdg's overlay name when this host is a
peer and the LAN address otherwise. That is why the special case retires
itself on the first run after enrolment rather than needing a follow-up
edit — and why the LAN reasoning stays live instead of decaying into a
comment about a branch nobody takes.

## Usage

Runs as the first role in `playbooks/nix-remote-builder.yml` — the ordering
matters, because the cache-push destination in `nix_remote_builder` can only
use the overlay name once this host is a peer.

```sh
task ansible:run-static -- playbooks/nix-remote-builder.yml
```

Idempotent; safe to re-run. On an enrolled host it does not touch 1Password.
