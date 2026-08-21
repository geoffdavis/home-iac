# NetBox → UDM DNS/DHCP Sync — Design

## Overview

Phase 2 of the NetBox/IPAM decision recorded in personal-notes: "Agent
Access and Deploy Coordination.md", section 5 (2026-08-21) — **NetBox goes
authoritative for IPAM/DNS, phased.** This spec covers the slice that lands
in this repo: turning `unifi_network_dns_record` and the DHCP-reservation
half of addressing into syncs *from* NetBox, instead of the hand-run source
of truth they are today.

**Redirected here from `ugreen-nas-compose`.** This work was originally
scoped against `ugreen-nas-compose` (see geoffdavis/ugreen-nas-compose#250
and the now-superseded spec/plan pair there, PR #251). Section 6 of the
same note subsequently decided to retire `ugreen-nas-compose` entirely and
fold its live Ansible work — the FreeIPA in-VM config and the UDM
integration roles — into `home-iac`, on the reasoning that neither fits
`pi-talos-home-ops` (would cohabit with the fleet's one unscoped
credential, cluster-admin kubeconfig) and both fit here better than a
shrinking single-purpose repo. This document is that redirect.

**Hard dependency, not yet done:** the actual Ansible roles
(`unifi_network_dns_record`, `unifi_network_dhcp_pxe`,
`unifi_network_port_forward`, and the four FreeIPA in-VM roles) do not
exist in this repo yet — only Terraform does today. **Migrating them here
is Task 1 of the implementation plan itself** — not separate,
not-yet-tracked work elsewhere. (Caught in review: an earlier draft of
this paragraph said the migration was "separate, tracked work" pointing
at "the companion issue for that migration," but no such issue exists —
the plan already scopes it as its own Task 1. Corrected here to match.)
Everything from Task 2 onward in the plan assumes Task 1 has landed and
been verified behavior-identical to the `ugreen-nas-compose` originals;
this spec describes the sync design on top of that, not the migration
mechanics themselves.

NetBox itself (the container, Phase 1) is `nix-personal` work
(geoffdavis/nix-personal#542) and is a separate dependency, unaffected by
the repo-retirement redirect.

## Why

Section 5 names three uncoordinated writers into the UDM: manual entries,
`pi-talos-home-ops`'s Cilium BGP + `external-dns`, and (today)
`ugreen-nas-compose`'s `unifi_network_dns_record` role — run "on a
schedule nobody but this repo knows." The role's own README already
admits this in its test-plan section: *"there's no shared source of truth
here, so a fleet edit to the list means updating this snippet too."* That
line is the bug this spec fixes, regardless of which repo it lives in.

The concrete cost, from the same night section 5 was written: reconstructing
VLAN 10's free DHCP range for pacificbeach's static IP took several live
UDM API calls, because nothing held the pool bounds or the in-use
addresses as a queryable table. **That specific gap — free/used address
lookup — is not covered by either existing role today.**
`unifi_network_dns_record` manages DNS aliases; `unifi_network_dhcp_pxe`
manages two network-wide DHCP options (next-server, boot filename), not
per-host reservations. Static IP assignment is currently 100% manual,
UDM-UI-only. This spec's highest-value piece is closing that gap, not just
relocating a role that already worked.

## Goals

- NetBox's IPAM becomes queryable for "what's free" and "what's assigned"
  on any tracked VLAN — closing the pacificbeach-style gap directly.
- Static DNS records (`unifi_network_dns_record`'s job today) are authored
  in NetBox, not in `host_vars`, and pushed to the UDM by a sync run.
- Static IP reservations (not currently automated at all) are authored in
  NetBox IPAM and pushed to the UDM's DHCP reservation list by a sync run.
- The sync is idempotent and safe to run on a schedule, replacing "run
  whenever someone remembers."
- Collapses two of section 5's three uncoordinated writers (manual UDM
  entries, the Ansible-role writer) into one: edit NetBox, then sync.

## Non-goals

- **`unifi_network_dhcp_pxe` does not move to NetBox in this phase.** Its
  two values (Option 66/67, the PXE next-server and boot filename) are
  network-wide settings, not host- or address-scoped — they don't fit
  NetBox's IPAM object model cleanly, and this role doesn't have the
  drift problem the DNS role does. Revisit only if it starts drifting.
- **No two-way sync.** NetBox is the write source; the UDM is never read
  back into NetBox after the Phase 1 import (see Design). A UDM-side
  manual edit after that point is drift to be *detected and overwritten*,
  not merged.
- **Phase 3 (Cilium/`external-dns` reconciliation) is not this repo's
  work.** Tracked separately in `pi-talos-home-ops`.
- **The detailed mechanics of the ugreen-nas-compose → home-iac Ansible
  migration** (Task 1 of the plan) — this spec assumes it's landed and
  verified; it doesn't re-derive how to do the migration itself.
- **Self-service reservation requests** are out of scope. NetBox stays
  operator-authored for now.

## Current state (as it will exist once the migration lands)

Both roles this spec touches already share a proven pattern, carried over
unchanged from `ugreen-nas-compose`:

- Cookie + CSRF auth against the UDM (`POST /api/auth/login`, rebuild
  `Cookie:`/`X-CSRF-Token:` per request), `delegate_to: localhost`.
- GET → diff → mutate only on drift, never an unconditional PUT.
- 1Password-sourced credentials (`community.general.onepassword` lookup),
  vault `Automation`, item `UniFi UDM Pro (ansible)` — shared across all
  `unifi_network_*` roles via a single "Limited Admin" UniFi account. This
  repo's existing convention (`.env` + `op run`, per `s3-iam-access.tf`'s
  header comment: "Access keys are managed in 1Password, not here") is
  already compatible with that pattern — same tool, different vault item.
- Static DNS specifically uses the v2 API
  (`/proxy/network/v2/api/site/<site>/static-dns`), identity key = `key` +
  `record_type`, and asserts on the returned `_id` rather than a
  `{meta: {rc: "ok"}}` envelope the v2 API doesn't return.

None of that changes in the move. What changes is **where desired state
comes from**: today it's `host_vars`; after this spec, it's NetBox.

## Design

### Data model in NetBox

- **Prefixes/VLANs** mirror the UDM's existing networks (Management,
  Private, IoT, NoT, etc. — see `[[Home Network Topology]]`). One NetBox
  Prefix per UDM VLAN, imported in Phase 1.
- **IP addresses** (`ipam.IPAddress`) represent static reservations.
  `status=dhcp` plus a DNS name is the natural fit for "pacificbeach gets
  `.31` on VLAN 10, and it's `pacificbeach.home.geoffdavis.com`."
- **DNS records** need a plugin — core NetBox has no zone/record model.
  Which plugin (`netbox-dns` is the obvious default) is an
  **implementation-time decision, not asserted here** — verify it's still
  maintained and compatible with the NetBox version Phase 1 deploys before
  committing. Fallback if none fits: `ipam.IPAddress`'s built-in DNS-name
  field, A/AAAA only.

### Sync direction and idempotency

One direction only: **NetBox → UDM.** But the comparison that drives it
must be a **full, symmetric set comparison**, not a one-directional walk
over NetBox's desired list — caught in review: the existing
`unifi_network_dns_record` role's `reconcile_one.yml` only ever iterates
the *desired* records and PUTs the ones that differ, so a role that keeps
that shape and merely swaps `host_vars` for a NetBox query would never
notice a UDM record that NetBox doesn't know about at all — neither a gap
in the Phase 1 backfill (which would make G3's "zero diff" claim false
even when it reports clean) nor a record legitimately deleted from NetBox
later (which would then never actually stop being pushed... except it
already isn't being pushed, it just silently stays live forever, since
nothing ever looks at it). Concretely:

1. Build set A: every key+record_type NetBox says should exist (desired
   state).
2. Build set B: every key+record_type currently on the UDM, **within the
   zone this sync manages** — filtered by the ownership check below
   *before* anything else touches it.
3. **Compare A and B as full sets, not just walk A:**
   - In A, not in B → create.
   - In both, values differ → update.
   - In both, values match → no-op.
   - **In B, not in A → this is the case the one-directional walk misses
     entirely.** Log it loudly (still never auto-delete — that stance is
     unchanged) but the comparison itself must actually run and be part
     of what a `--check` reports, so G3's zero-diff gate is checking the
     whole set, not just NetBox's half of it. Without this, G3 can pass
     on an incomplete backfill and nobody would know.

**Ownership filter, and where it actually has to live:** skip any UDM
record carrying `external-dns`'s ownership TXT marker
(`pi-talos-home-ops`) when building set B in step 2 above — this phase
manages the *static* half of the zone, not the Kubernetes-originated half.
**This has to be real code, not just a stated intent:** `reconcile_one.yml`
today selects a record purely by `key` + `record_type`, with no awareness
of TXT ownership siblings at all. If NetBox ever holds a record with the
same key+type as something `external-dns` manages, the reconciler as
currently structured would happily overwrite a live Kubernetes-owned DNS
record. Task 3 of the plan must add an explicit step that queries the
UDM (or wherever the TXT markers are visible) for `external-dns`-owned
names, builds an exclusion set from them, and applies that exclusion when
building set B — before the record-selection logic in `reconcile_one.yml`
ever runs, not as an afterthought bolted onto it.

### Roles

- **`unifi_network_dns_record`** — rewritten once migrated here. Its
  `records` list stops coming from `host_vars` and instead comes from a
  NetBox query at playbook-run time. UDM-side logic unchanged.
- **New role, `unifi_network_ip_reservation`** (name TBD — check for a
  clearer fit against the `unifi_network_*` convention once migrated).
  Reads NetBox `status=dhcp` IP addresses for tracked prefixes, pushes
  them to the UDM's DHCP fixed-reservation list — an endpoint neither
  existing role currently touches. This is the role that closes the
  pacificbeach-style gap.
- **`unifi_network_dhcp_pxe`** — unchanged. See Non-goals.

### Credentials

- UniFi UDM: same 1Password item this role already uses today in
  `ugreen-nas-compose`, no new UDM-side credential — just a new consumer
  once the role moves.
- NetBox, **two separate tokens, not one:**
  - **Ongoing sync** (Task 3 onward): read-only, if NetBox's permission
    model supports it — this token only ever queries desired state.
  - **One-time backfill** (Task 2, `netbox_import_udm_state`): **must be
    write-scoped.** Caught in review: the backfill role's whole job is
    creating/updating NetBox objects from what it reads off the UDM, so a
    read-only token can't do it — an earlier draft of this spec only
    specified the read-only sync token and never gave the backfill
    anything capable of writing. Store as its own 1Password item, used
    only for the one-time (or manually re-run) import, not the scheduled
    sync.

### Schedule

A systemd timer or CI cron — match whatever this repo's Ansible tooling
ends up using once Task 1's migration lands (that task decides the
convention; not asserted here).

### Phase 1 import

Before this repo's sync role can run meaningfully, NetBox needs to be
seeded with the UDM's *current* static-DNS records and any de-facto static
reservations. One-time, reads-from-UDM/writes-to-NetBox (see Credentials
above for why that direction needs its own token). This is Task 2 of the
implementation plan, blocked on Task 1 (the Ansible migration) and on
geoffdavis/nix-personal#542 (NetBox actually running).

## Migration plan (high level)

1. **G0 — prerequisite.** Plan Task 1 (the Ansible-roles migration) has
   landed: `unifi_network_dns_record`, `unifi_network_dhcp_pxe`,
   `unifi_network_port_forward` exist in this repo, unchanged from
   `ugreen-nas-compose`, and run successfully from here.
2. **G1 — NetBox reachable and importable.** `nix-personal#542` deployed;
   confirm reachability; resolve the DNS-plugin question.
3. **G2 — Backfill.** Import script (using the write-scoped token —
   Credentials) populates NetBox from the UDM's current static-DNS
   records and known static-ish reservations. Spot-check against the UDM
   UI.
4. **G3 — `unifi_network_dns_record` rewritten, dry-run clean — proven,
   not assumed.** `--check` produces zero diffs against the UDM's current
   state, **using the full symmetric-set comparison from Design** (both
   directions checked, not just NetBox's desired list walked forward) —
   a zero-diff result under the old one-directional walk could pass on an
   incomplete backfill without anyone knowing; this gate only means
   something once the comparison it's checking is actually complete.
5. **G4 — First real write.** One DNS record changed in NetBox, synced,
   verified with `dig`.
6. **G5 — `unifi_network_ip_reservation` built and exercised.** One new
   reservation, created in NetBox, verified present in the UDM.
7. **G6 — Schedule wired up**, old manual-run convention retired.

## Risks

| Risk | Severity | Retired by |
|---|---|---|
| Migration (G0) lands the roles but with subtle drift from `ugreen-nas-compose`'s originals | Medium | Diff the migrated role files against the source repo before G0 is called done |
| DNS plugin choice turns out unmaintained/incompatible | Medium | Resolved as G1, before the sync role is written against it |
| Backfill (G2) misses records, and the old one-directional G3 check wouldn't have caught it | High | Fixed by the full symmetric-set comparison (Design) — G3 now checks both directions, not just NetBox's list |
| Sync overwrites a Cilium/`external-dns`-owned record because the ownership filter was only ever asserted, not implemented in `reconcile_one.yml`'s actual selection logic | High | Design now specifies exactly where the filter has to be wired in, and plan Task 3 makes it an explicit step, not an afterthought |
| Backfill (Task 2) has no credential capable of writing to NetBox | High (would block G2 entirely) | Fixed by the separate write-scoped backfill token (Credentials) |
| Two-way drift after cutover | Medium, ongoing | Sync overwrites on next scheduled run (NetBox wins) |

## Open questions

- Exact DHCP-reservation API shape on the UDM (verify live, same as the
  pacificbeach pool-bounds check).
- Whether `unifi_network_ip_reservation` is a new role or an extension of
  `unifi_network_dns_record`.
- Whether `unifi_network_dhcp_pxe` ever moves under NetBox — deferred.
- **What this repo's name/README should say once it's Terraform + Ansible
  for two different platforms** — out of scope for this spec, but the
  README's current "OpenTofu configuration for home lab AWS
  infrastructure" framing will need a line acknowledging the Ansible half
  once the migration lands.

## Out of scope

- Phase 1 (NetBox hosting) — `nix-personal#542`.
- Phase 3 (Cilium/`external-dns` reconciliation) — `pi-talos-home-ops`.
- The detailed mechanics of the Ansible-roles migration — plan Task 1
  covers execution; this spec assumes it's done.
- `ugreen-nas-compose`'s archival, once empty — section 6's job, not this
  spec's.

## References

- personal-notes: "Agent Access and Deploy Coordination.md", sections 3,
  5, and 6
- geoffdavis/ugreen-nas-compose#250 and PR #251 — superseded by this
  document; left open there with a pointer, not closed
- geoffdavis/nix-personal#542 — NetBox hosting (dependency)
- geoffdavis/home-iac#6 — the unrelated-but-adjacent Longhorn credential
  cleanup already in flight in this repo (PR #5)
