# NetBox → UDM DNS/DHCP Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make NetBox the authored source of truth for UDM static DNS
records and static IP reservations, replacing `unifi_network_dns_record`'s
`host_vars`-driven records and the current 100%-manual reservation process,
with an idempotent scheduled sync — running from `home-iac`, not
`ugreen-nas-compose`, per the repo-retirement decision in personal-notes:
"Agent Access and Deploy Coordination.md" section 6.

**Architecture:** Same as originally scoped against `ugreen-nas-compose`
(see geoffdavis/ugreen-nas-compose#250 and its superseded spec/plan, PR
#251) — `unifi_network_dns_record` sourced from NetBox instead of
`host_vars`, a new role for IP reservations, one-way NetBox → UDM sync. The
only change from that original scope is **where it runs**, and the new
Task 1 prerequisite: the Ansible roles have to exist in this repo before
anything else here makes sense.

**Tech Stack:** Ansible (once migrated — see Task 1), NetBox REST API
(token auth), UniFi UDM Pro REST API (cookie+CSRF, existing pattern from
the roles being migrated), 1Password (`op run`, this repo's existing
convention), pytest.

**Spec:** `docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md`

**Scope note:** This repo has no Ansible in it today — only OpenTofu. Task
1 (migrating the live roles from `ugreen-nas-compose`) is a hard
prerequisite for every task after it and is itself a separate, real piece
of work — don't treat it as a formality.

---

## Pre-flight facts to verify before Task 2

- Which NetBox DNS plugin (if any) Phase 1 (geoffdavis/nix-personal#542)
  actually installs, and its API shape. See spec Open Questions.
- The UDM's DHCP fixed-reservation API endpoint and payload shape —
  neither existing role touches reservations today; verify live.
- Whether this repo's OpenTofu-era tooling (`Taskfile.yml`,
  `.pre-commit-config.yaml`) needs new entries for Ansible (lint hooks,
  `task` targets) as part of Task 1, or whether that's simple enough to
  fold into Task 1 directly.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `ansible/` *(create — new top-level dir, Task 1)* | Migrated from `ugreen-nas-compose`: `roles/{nixos_freeipa_vm,freeipa_autopatch,freeipa_metrics,freeipa_rsyslog,unifi_network_dns_record,unifi_network_dhcp_pxe,unifi_network_port_forward}/`, `playbooks/`, `inventory.yml`, `host_vars/` |
| `ansible/roles/unifi_network_dns_record/tasks/main.yml` *(modify, post-migration)* | Replace `host_vars`-sourced `records` with a NetBox API query task |
| `ansible/roles/unifi_network_dns_record/defaults/main.yml` *(modify)* | Add `unifi_network_dns_record_netbox_*` vars; keep `unifi_network_dns_record_records` as a temporary escape hatch |
| `ansible/roles/unifi_network_ip_reservation/` *(create)* | New role: NetBox `status=dhcp` IPs → UDM DHCP fixed reservations |
| `ansible/roles/netbox_import_udm_state/` *(create, one-shot)* | Backfill: UDM → NetBox, run once |
| `ansible/playbooks/unifi-network.yml` *(modify)* | Add the new reservation role |
| `ansible/playbooks/netbox-import.yml` *(create, one-shot)* | Wraps the backfill role |
| `.pre-commit-config.yaml` *(modify)* | Add ansible-lint alongside the existing OpenTofu hooks |
| `Taskfile.yml` *(modify)* | Add `ansible:*` targets alongside the existing `init`/`plan`/`apply` |
| `README.md` *(modify)* | Update "What it manages" to include the FreeIPA/UDM half |
| systemd timer or CI cron *(create, location TBD)* | Scheduled sync |

---

### Task 1: Migrate the live Ansible roles from `ugreen-nas-compose`

**Files:** Create `ansible/` (see File Structure); modify
`.pre-commit-config.yaml`, `Taskfile.yml`, `README.md`

**This is the prerequisite for everything else in this plan.** Treat it as
its own reviewable unit — a straight migration commit, with the NetBox
rewrite (Task 3+) as a clean follow-on, not mixed into the same change.

- [x] **Step 1: Copy `ansible/roles/{nixos_freeipa_vm,freeipa_autopatch,
  freeipa_metrics,freeipa_rsyslog,unifi_network_dns_record,
  unifi_network_dhcp_pxe,unifi_network_port_forward}/`** from
  `ugreen-nas-compose` verbatim — no changes yet. Preserve git blame if
  practical (e.g. `git subtree`/`git format-patch` rather than a raw
  copy, if history continuity matters here). Done via `git-filter-repo` +
  `git merge --allow-unrelated-histories` — history preserved, verified
  byte-identical to the source at copy time.
- [x] **Step 2: Copy `ansible/playbooks/`, `ansible/inventory.yml`, and
  the relevant `host_vars/`** — only what these seven roles need, not
  `ugreen-nas-compose`'s full inventory (which also covers the now-dropped
  `truenas_*`/orphaned roles per geoffdavis/ugreen-nas-compose#249 — don't
  bring those over even by accident). Also dropped the `oob_kvm` (JetKVM)
  group, which none of these roles touch either.
- [x] **Step 3: Confirm the 1Password items these roles reference**
  (`UniFi UDM Pro (ansible)`, the FreeIPA credentials) are reachable from
  this repo's existing `op run` convention — same 1Password vault, just a
  new consumer repo. Confirmed live.
- [x] **Step 4: Add ansible-lint to `.pre-commit-config.yaml`**, matching
  whatever config `ugreen-nas-compose` used, adapted to this repo's
  pre-commit conventions. `ugreen-nas-compose` never had ansible-lint
  wired up at all — added fresh, see `.ansible-lint`'s header comment.
- [x] **Step 5: Add `task ansible:*` targets to `Taskfile.yml`** —
  `ansible:check` (lint/syntax-check), `ansible:run` (the playbooks) —
  matching this repo's existing `task plan`/`task apply` naming spirit.
  Also added `ansible:install`.
- [x] **Step 6: Run every migrated playbook in check/dry-run mode**
  against the real FreeIPA VM and UDM, confirm zero unexpected diffs —
  this proves the migration didn't silently change behavior before Task 2
  even starts. Done — see PR #10 for the full per-playbook results
  (clean across the board, with one pre-existing check-mode gap in the
  three `unifi_network_*` roles fixed live to make the proof possible,
  and `nixos_freeipa_vm`'s check-mode limitation documented rather than
  worked around).
- [x] **Step 7: Update `README.md`**'s "What it manages" section to
  include FreeIPA replica management and UDM integration alongside the
  existing S3/IAM description.
- [x] **Step 8: Commit as its own PR**, separate from the NetBox-rewrite
  work that follows. PR #10 (geoffdavis/home-iac), not yet merged.

### Task 2: One-shot backfill — import UDM state into NetBox (Gate G2)

**Files:** Create `ansible/roles/netbox_import_udm_state/`,
`ansible/playbooks/netbox-import.yml`

Blocked on Task 1 and on geoffdavis/nix-personal#542 (NetBox running).

- [ ] **Step 1: Create a write-scoped NetBox API token**, its own
  1Password item, separate from the read-only token Task 3 uses for the
  ongoing sync. **Caught in review: this role creates/updates NetBox
  objects — a read-only token can't do its job**, and an earlier draft of
  this plan only ever specified a read-only NetBox credential anywhere in
  the design. Don't reuse or upgrade the ongoing-sync token's scope;
  keep them separate so the scheduled sync never holds write access.
- [ ] **Step 2: GET the UDM's current static-DNS list** (reuse
  `unifi_network_dns_record`'s v2 endpoint and auth, now migrated here).
- [ ] **Step 3: For each record, create or update the matching NetBox
  object** (per the spec's DNS-plugin decision), using Step 1's
  write-scoped token.
- [ ] **Step 4: GET known static-ish addresses**, seeded from the
  documented low addresses in section 5's pacificbeach data point, cross-
  checked against the UDM's actual DHCP lease/reservation state.
- [ ] **Step 5: Spot-check a sample in the NetBox UI against the UDM UI.**
- [ ] **Step 6: Commit.**

### Task 3: Rewrite `unifi_network_dns_record` to source from NetBox

**Files:** Modify `ansible/roles/unifi_network_dns_record/tasks/main.yml`,
`defaults/main.yml`, `README.md`

- [ ] **Step 1: Add NetBox connection vars** to `defaults/main.yml`
  (URL, read-only 1Password creds item — separate from Task 2's
  write-scoped one — and a temporary `unifi_network_dns_record_records`
  escape hatch — same pattern as the original ugreen-nas-compose-scoped
  plan).
- [ ] **Step 2: Add the NetBox query task**, gated by the escape hatch —
  this is set A from the spec's Design (desired state).
- [ ] **Step 3: Add the `external-dns` ownership-exclusion query.**
  **This did not exist in the original draft of this plan and is not
  optional** — caught in review: without it, this role can overwrite a
  live Kubernetes-owned DNS record the moment NetBox happens to hold a
  record with the same key+type. Query the UDM (or wherever the TXT
  ownership markers are actually visible — confirm at implementation
  time) for names owned by `external-dns`, build an exclusion set.
- [ ] **Step 4: Add the full-UDM-state query**, filtered by Step 3's
  exclusion set — this is set B from the spec's Design.
- [ ] **Step 5: Modify `reconcile_one.yml`'s selection logic** to operate
  on the A/B comparison from the spec (create / update / no-op / log-only
  for B-not-in-A), not the existing walk-only-the-desired-list shape.
  This is a real behavior change to existing, working code — review it
  as carefully as new code, not as a mechanical rename.
- [ ] **Step 6: Transform the NetBox response into the role's existing
  record-dict shape** for the create/update cases.
- [ ] **Step 7: `--check` against a backfilled NetBox, confirm zero
  diffs (Gate G3) — using the full A/B comparison from Steps 3-5, not
  just "does NetBox's list match."** A clean result under the old
  one-directional walk would not have proven the backfill was complete;
  this gate only means something now that the comparison itself checks
  both directions.
- [ ] **Step 8: Deliberately test the exclusion filter** — create a
  NetBox record with the same key+type as a known `external-dns`-managed
  UDM record, confirm the sync does *not* touch it, before trusting Step
  5's logic on real data.
- [ ] **Step 9: Update the README.**
- [ ] **Step 10: Commit.**

### Task 4: First real NetBox-sourced write (Gate G4)

Same procedure as the original plan: change one low-risk record in
NetBox, sync for real, verify with `dig`, revert and confirm the revert
syncs cleanly too.

- [ ] **Step 1–4** as above.

### Task 5: New role — NetBox IP reservations → UDM (Gate G5)

**Files:** Create `ansible/roles/unifi_network_ip_reservation/`; modify
`ansible/playbooks/unifi-network.yml`

- [x] **Step 1: Write `defaults/main.yml`.** Done.
- [x] **Step 2: Write the NetBox query task** — resolve the MAC/interface
  association question from the spec's Design section before the
  transform. Resolved: `ipam.IPAddress` carries no MAC of its own — it
  lives on the interface reached via `assigned_object_type` +
  `assigned_object_id` (`dcim.Interface` / `virtualization.VMInterface`),
  fetched with a second per-address GET. This fleet runs NetBox v4.6
  (`hosts/nas-sdg/apps/netbox.nix`), which moved MACs onto a dedicated
  `dcim.MACAddress` object in 4.2 — the resolution task reads both the
  interface's `mac_address` and `primary_mac_address.mac_address` to
  tolerate either shape. See
  `ansible/roles/unifi_network_ip_reservation/README.md`'s "MAC/interface
  design question" section. Unverified against a live NetBox response —
  the escrowed API token doesn't currently authenticate (see Step 4).
- [x] **Step 3: Write the UDM-side GET → diff → apply task** once the
  DHCP-reservation endpoint is confirmed live. Confirmed live
  2026-08-24: `/proxy/network/api/s/default/rest/user` (legacy v1 REST
  "known client" objects, `use_fixedip`/`fixed_ip`/`network_id` fields,
  same `{data, meta}` envelope `unifi_network_port_forward` uses) — 50
  existing `use_fixedip` clients found on the real controller. See the
  role README's "UDM endpoint" section for the transcript.
- [x] **Step 4: `--check` dry run against a known-static address.** Done
  against the live UDM for both nas-sdg (172.29.10.20) and pacificbeach
  (172.29.10.31), feeding `reconcile_one.yml` real UDM-observed MACs by
  hand (NetBox's own token doesn't authenticate — see role README).
  Both correctly detect drift on the proven PUT/update path; zero writes
  performed. Full transcript and the NetBox-token caveat are in the role
  README.
- [ ] **Step 5: Real run for a genuinely new reservation.** **Not done —
  deliberately stopped here.** NetBox has no real backfilled data yet
  (Task 2 in flight in parallel) and its token doesn't authenticate, so
  there's no genuine NetBox-authored reservation to drive a real run
  with; the one UDM code path a hand-picked "new" reservation would most
  plausibly exercise (`POST` for a never-before-seen MAC) is exactly the
  path Step 3 could not verify live. See the role README's "No real
  write performed" section for the reasoning and recommended next step.
- [x] **Step 6: Add the role to `unifi-network.yml`.** Done — added,
  but left un-enabled in every host's `host_vars` (opt-in default
  `false` only) pending Task 2's backfill and Step 5.
- [x] **Step 7: Write the README.** Done —
  `ansible/roles/unifi_network_ip_reservation/README.md`.
- [x] **Step 8: Commit.** This PR.

### Task 6: Remove the escape hatch

- [ ] Confirm no `host_vars/*.yml` still sets
  `unifi_network_dns_record_records`, remove the var and the
  short-circuit, commit.

### Task 7: Schedule the sync (Gate G6)

- [ ] Wire up a systemd timer or CI cron running
  `ansible/playbooks/unifi-network.yml` on an hourly-or-so interval.
  Update the operator runbook: DNS/reservation edits happen in NetBox now,
  not the UDM UI and not `host_vars`. Commit.

---

## Definition of done

- [ ] Task 1's migration merged as its own reviewable unit, verified
  behavior-identical to `ugreen-nas-compose` before any rewrite started.
- [ ] All gates G2–G6 passed.
- [ ] Escape hatch removed (Task 6).
- [ ] Sync runs on a schedule (Task 7).
- [ ] `README.md` reflects the repo's real, two-platform scope.
- [ ] Lint passes (OpenTofu + the new ansible-lint hook).
