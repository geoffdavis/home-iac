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
  short-circuit, commit. **Blocked for any host whose static list has a
  CNAME, NS, wildcard, or non-NetBox-tracked-IP record (nas-sdg, today)
  until Task 8 lands** — see that task for why the `ipam.IPAddress`
  fallback can't represent them, so those hosts can drop the escape
  hatch only after their records have a home in netbox-dns.

### Task 7: Schedule the sync (Gate G6)

- [ ] Wire up a systemd timer or CI cron running
  `ansible/playbooks/unifi-network.yml` on an hourly-or-so interval.
  Update the operator runbook: DNS/reservation edits happen in NetBox now,
  not the UDM UI and not `host_vars`. Commit.

### Task 8: Install netbox-dns, migrate DNS records to a full record model (Gate G7)

**Files:** nix-personal (plugin install/config — separate repo, separate
PR, not tracked here); create
`ansible/roles/netbox_import_udm_dns_records/` (or extend Task 2's
`netbox_import_udm_state`); modify `ansible/filter_plugins/netbox_sync.py`,
`ansible/roles/unifi_network_dns_record/{tasks/main.yml,
tasks/netbox_fetch_page.yml, defaults/main.yml, README.md}`.

Surfaced during Task 3's live verification (PR #16, live `--check --diff`
against nas-sdg): the `ipam.IPAddress.dns_name` fallback Task 3 shipped is
A/AAAA-only, and structurally can't represent a CNAME or NS record, a
wildcard (`*.`) name, or any record whose value isn't itself a
NetBox-tracked IP address. Real, currently-live records on nas-sdg that
fall in this gap: `syslog.home.geoffdavis.com` (CNAME),
`ipa.geoffdavis.com` (NS), `*.nas`/`*.admin`/`*.media.home.geoffdavis.com`
(wildcards), and the split-horizon `nas.home.geoffdavis.com` /
`admin.home.geoffdavis.com` pair (A records pointing at the netbird
overlay IP `100.92.233.103`, which NetBox's IPAM has no reason to ever
track). A host left on `unifi_network_dns_record_source: netbox` today
stops actively managing these — they're logged as orphans, never
recreated if deleted — which is why Task 3 kept `static` as the default
rather than cutting nas-sdg over.

netbox-dns models DNS records as first-class `Record` objects (Zone +
Record, arbitrary `type`, arbitrary string `value` — not derived from
`ipam.IPAddress`), which removes all three limitations at once. This was
always the design spec's stated preference (Open Questions: source from
the plugin directly if installed; `ipam.IPAddress` was explicitly the
fallback) — Task 3 used the fallback only because the plugin wasn't
installed at implementation time, confirmed live via `GET /api/status/`
returning `"plugins":{}` on 2026-08-24.

**Status: plugin install (Step 1) done.** Confirmed live 2026-08-26 via
`GET /api/status/`: `"plugins": {"netbox_bgp": "0.19.0", "netbox_dns":
"1.5.11"}`. `netbox-bgp` came along with the same effort but is out of
scope for this task. The plugin's REST surface is up
(`/api/plugins/netbox-dns/{zones,records,nameservers,views,
registrars,contacts,prefixes,...}/`); `zones` count is currently 0 — Step
2 hasn't happened yet. The read-only token this repo already has
(`netbox-ansible-inventory-token`) can't show the POST schema for these
endpoints (DRF only includes it for a token with add permission), so
Step 3's write-scoped-token question — reuse Task 2's
`netbox-udm-import-token` (unconfirmed whether its permissions cover
netbox-dns's object types, since it was originally scoped for
`ipam.IPAddress`) vs. mint a new one — resolved: neither
`netbox-udm-import-token` nor `netbox-ansible-inventory-token` is the
write credential in use initially. A separate token, 1Password
`op://nas-overlay/netbox-geoff-token/token`, had full write access
(tied to `geoff`'s own superuser account) and is what Step 2 actually
used to create the Zone/View/NameServer.

**Since resolved properly**, per the user's request that agentic edits
be attributable separately from their own: created a dedicated NetBox
user `ansible` (id 4, local account — not LDAP-bound, which is fine
since DRF `TokenAuthentication` looks up the Token row directly and
never goes through the LDAP login/bind flow), an `ObjectPermission`
(`ansible-netbox-dns-write`, id 1) scoped to
`view`/`add`/`change` on `netbox_dns.{view,nameserver,zone,record}`
only, and a token for that user/permission pair. Stored at 1Password
`op://nas-overlay/netbox-ansible-service-account/credential` (vault
`nas-overlay`). **Live-verified 2026-08-26**: succeeds on
`netbox_dns` reads/writes, 403s on `ipam.ipaddress` and `users` (proof
the scoping is actually restrictive, not just additive) — deliberately
excludes `delete`, matching this sync's "never auto-delete, only log
orphans" principle elsewhere.

Two non-obvious things worth keeping in institutional memory:
- `POST /api/users/tokens/` returns the secret split across TWO fields
  (`key`, a 12-char id matching the `display` field, and `token`, the
  secret suffix) — neither works alone as a Bearer value. The complete
  credential is the concatenation `"nbt_" + key + "." + token`. Cost two
  failed rotations to work out live.
- `netbox-udm-import-token` (Task 2) and `netbox-ansible-inventory-token`
  (dynamic inventory, PR #13) still run under `geoff`/`admin`, not this
  new `ansible` account — migrating them is a separate, more invasive
  change (both are already live/merged) and deliberately out of scope
  here.

- [x] **Step 1: Install and configure the netbox-dns plugin** on
  nas-sdg's NetBox instance (nix-personal, `hosts/nas-sdg/apps/netbox.nix`)
  — done, confirmed live 2026-08-26 (`netbox_dns` 1.5.11).
- [x] **Step 2: Create the `home.geoffdavis.com` Zone.** Done
  2026-08-26 via `op://nas-overlay/netbox-geoff-token/token`:
  - View `Internal` (id 2) — the LAN-only split-horizon perspective;
    the public `home.geoffdavis.com` apex is a single CNAME to dynamic
    DNS at the registrar, deliberately not modeled here (out of scope
    for this sync, which only ever writes to the UDM).
  - NameServer `unifi.home.geoffdavis.com.` (id 1) — bookkeeping only;
    nothing queries it as a real NS, since the UDM (not netbox-dns)
    answers LAN queries.
  - Zone `home.geoffdavis.com` (id 1), `view=Internal`, `status=active`,
    `soa_serial_auto=true`, conventional SOA timers
    (refresh/retry/expire/minimum = 172800/7200/2419200/3600 — no
    fleet-wide defaults exist, confirmed via
    `hosts/nas-sdg/apps/netbox-plugins.py`'s empty `PLUGINS_CONFIG`).
  - Checked: nas-sdg is the *only* host with `unifi_network_dns_record_records`
    set (`grep -rl unifi_network_dns_record_records ansible/host_vars/`),
    so no other host contributes a second apex. One nuance within
    nas-sdg's own list, though: the `ipa.geoffdavis.com` NS record is a
    genuinely different zone from `home.geoffdavis.com`, not a
    subdomain of it — and its value (`172.29.50.21`, an IP) is an odd
    shape for an NS record's target regardless. Likely a legacy
    delegation pointer to the FreeIPA VM (see the role README's
    `playbooks/freeipa-dns-records.yml` cross-reference) rather than
    something this sync should model as a `home.geoffdavis.com` A/CNAME
    peer. Step 3 needs to explicitly decide: skip it (FreeIPA's own DNS
    already owns that zone) or give it a real second Zone — don't let it
    silently fall into whatever `home.geoffdavis.com`-shaped bucket the
    backfill script defaults to.
- [ ] **Step 3: One-shot backfill role**
  (`netbox_import_udm_dns_records`, or extend Task 2's
  `netbox_import_udm_state`) — same shape as Task 2: GET the UDM's
  current static-DNS list, create/update the matching netbox-dns
  `Record` object for each, using a write-scoped token separate from the
  ongoing-sync's read-only one (same separation rule as Task 2 Step 1).
  Covers every record type, not just A/AAAA — including the ones Task
  2's original backfill couldn't represent.
- [ ] **Step 4: Revive `netbox_dns_records_to_udm`** — the plugin-shaped
  transform PR #9 originally wrote and unit-tested, deliberately dropped
  from PR #16 when the plugin was confirmed absent. Re-adapt it against
  netbox-dns's actual live API shape rather than assuming PR #9's
  version is still correct — verify field/endpoint names against the
  real, now-installed plugin. This is the same live-verify-before-trust
  discipline that caught two real bugs in the `ipam.IPAddress` fallback
  during Task 3 (a pagination `None` crash and a mis-decoded
  external-dns TXT-ownership key format) — assume this plugin's actual
  shape has its own surprises too.
- [ ] **Step 5: Point the role's NetBox records endpoint at netbox-dns**
  instead of `ipam/ip-addresses/`. Keep `unifi_network_dns_record_source`
  as the mode switch (`static` / `netbox`) — this changes what "netbox
  mode" fetches, not the role's external interface.
- [ ] **Step 6: `--check` against the backfilled netbox-dns data,
  confirm zero diffs across every record type this fleet actually has**
  (CNAME, NS, wildcard, split-horizon A) — not just the A/AAAA subset
  Task 3's Gate G3 covered.
- [ ] **Step 7: Update the README's "Why `ipam.IPAddress`, not a
  DNS-record object" section** — no longer true once this lands; replace
  with the netbox-dns data model description.
- [ ] **Step 8: Flip nas-sdg's `host_vars` to `unifi_network_dns_record_source: netbox`**
  now that its CNAME/NS/wildcard/split-horizon records have a home —
  this is what actually unblocks Task 6 for this host. Side benefit,
  confirmed in Task 3's dry run: this also resolves a latent conflict
  where the static list's `website-dev.k8s`/`website-prod.k8s` entries
  point at the wrong address (the LB pool's network address, not a real
  host) — netbox mode excludes both as external-dns-owned instead of
  fighting the live Kubernetes reconciliation every run.
- [ ] **Step 9: Commit.**

---

## Definition of done

- [ ] Task 1's migration merged as its own reviewable unit, verified
  behavior-identical to `ugreen-nas-compose` before any rewrite started.
- [ ] All gates G2–G7 passed.
- [ ] Escape hatch removed (Task 6) for every host, including the ones
  that needed Task 8's full record model first.
- [ ] Sync runs on a schedule (Task 7).
- [ ] `README.md` reflects the repo's real, two-platform scope.
- [ ] Lint passes (OpenTofu + the new ansible-lint hook).
