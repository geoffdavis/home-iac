# Agent notes for home-iac

Conventions that aren't obvious from reading the code. Read this before
making changes.

## Credentials

Never put AWS, NetBox, UDM, or FreeIPA credentials in env vars, `.tfvars`,
or committed files. Everything is 1Password-backed and injected at run time
via `op run --env-file .env -- <command>` — `Taskfile.yml` already wraps
this (`task init`, `task plan`, `task apply`, `task ansible:run`, etc.). Use
the Task targets rather than calling `tofu`/`ansible-playbook` directly.

The OpenTaco Cloud state backend is a separate credential: a CLI token from
`tofu login otaco.app`, stored in `~/.terraform.d/credentials.tfrc.json`,
not 1Password. `task init`/`plan`/`apply` need both this and the AWS creds.

## OpenTofu (`environments/home`)

- State lives in OpenTaco Cloud (`cloud.tf`), not S3. A `cloud` block and a
  `backend` block cannot coexist in the same module — don't add a `backend`
  block back in.
- `state-backend.tf`'s S3 bucket + DynamoDB table are a legacy backend, kept
  as plain resources rather than destroyed. They are not read from or
  written to as a backend.
- `task init` uses the committed `.terraform.lock.hcl` as-is (reproducible).
  Use `task init-upgrade` only when deliberately bumping provider versions
  — don't change `task init` to always `-upgrade`.
- `environments/home/github-oidc.tf`'s IAM policy is deliberately scoped by
  explicit resource ARN to just what this environment manages, not
  wildcarded. When adding a new AWS resource here that CI needs to manage
  (create/update/delete), extend that policy's resource list — an
  `AccessDenied` from the Digger CI role on a new resource type is expected
  first-run friction, not a bug to route around with broader permissions.

## PR automation (Digger / OpenTaco)

- `digger.yml` at repo root defines the Digger/OpenTaco project(s)
  (currently one: `environments/home`). Without an entry here for a
  directory, Digger silently no-ops on PRs touching it.
- `.github/workflows/digger_workflow.yml` is a `workflow_dispatch` job.
  It's dispatched by the OpenTaco Cloud GitHub App (already installed on
  this repo) with a computed `spec` — there is no separate repo-hosted
  "trigger" workflow to look for.
- AWS auth for that job is OIDC (`aws-role-to-assume`, backed by
  `github-oidc.tf` and the `AWS_DIGGER_ROLE_ARN` repo Actions variable).
  Never reintroduce static `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` repo
  secrets for this workflow.

## CI (`.github/workflows/ci.yml`)

- `actions/setup-python` installs both `3.13` and `3.14` deliberately: the
  `ansible-lint` pre-commit hook is pinned to `v26.1.1` specifically because
  it's the last release whose hook venv works with `python3.13`. Don't drop
  3.13 from that step, and don't bump `ansible-lint` past that pin without
  checking whether its hook now needs a different interpreter than what's
  installed here.
- Never bypass pre-commit hooks (`--no-verify`) to get a commit through. If
  a hook fails, fix the underlying issue.

## Scheduled Ansible reconciliation

- `.github/workflows/ansible-reconcile.yml` re-runs the idempotent playbooks
  (FreeIPA day-2 ops, UniFi UDM network sync) daily — Ansible's substitute
  for Puppet-style continuous enforcement, since a play only converges
  state when something actually re-runs it.
- Runs on `[self-hosted, nix, x86_64-linux, nas-sdg]`, not the generic
  self-hosted pool — this job needs LAN reachability to the UDM/FreeIPA
  replicas and to nas-sdg's 1Password Connect server (`172.29.10.20:8081`),
  none of which the `nas-sct`/`nas-cin` runner spokes have. Both the runner
  and the Connect server are provisioned in the separate `nix-personal`
  repo (`hosts/nas-sdg/default.nix`'s `my.ghRunners.repos`,
  `hosts/nas-sdg/apps/onepassword-connect.nix`) — not something to touch
  from this repo.
- `ansible-playbook`/`ansible-galaxy` come from the runner's own nix package
  set (`gh-runners.nix`'s `extraPackages`), not installed at workflow
  runtime. A `uv sync`-based runtime install was tried first and hit two
  dead ends — `uv` missing from the runner's PATH, then a uv-managed Python
  download that failed to exec under the runner unit's own systemd
  sandboxing — before landing on baking the package in instead.
- Credentials come from 1Password **Connect**, not a Service Account (this
  account is on a Family plan, which doesn't support Service Accounts) —
  `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` env vars, which `op` uses
  transparently in place of a desktop-app session. The `OP_CONNECT_TOKEN`
  repo secret is the Connect server's own bearer token (1Password item
  `nas-sdg-onepassword-connect` in `nas-overlay`, field `credential`).
- Connect is scoped **read-only to the `nas-overlay` vault only**. The
  workflow uses `ansible/.env.ci` (NetBox token only — deliberately not the
  repo-root `.env`, which references `op://Private/...` AWS keys Connect
  can't resolve) and overrides each `unifi_network_*` role's
  `*_creds_op_vault` to `nas-overlay`, since those roles default to the
  `Automation` vault. The UDM credential item (`UniFi UDM Pro (ansible)`)
  is deliberately duplicated into `nas-overlay` for this workflow rather
  than expanding Connect's scope — keep both copies in sync if the UDM
  credential ever rotates.
- The `ipa_replicas` group (FreeIPA autopatch/metrics/rsyslog) uses a
  dedicated IPA service account, `svc-ansible`, not the local-only `rocky`
  cloud-init user — an IPA-managed identity that works fleet-wide (all
  replicas share the same LDAP-backed sudo rule) rather than a per-VM local
  account with no central audit trail. Set only via `-e ansible_user=` /
  `-e ansible_ssh_private_key_file=` on the FreeIPA play invocations in
  this workflow — `inventory.yml`'s default `ansible_user: rocky` is
  untouched, so local/interactive runs are unaffected. The key is
  `home-iac-ci-freeipa-ssh-key` (nas-overlay), set as `svc-ansible`'s
  `ipaSshPubKey`.
  - `svc-ansible-sudo` (an IPA sudo rule) grants it passwordless sudo,
    scoped by identity (`svc-ansible-group` membership) and by command
    (`/usr/bin/python3*` — matching what Ansible's `become` actually
    invokes, an AnsiballZ-wrapped Python script, not a fixed binary+args
    sudoers could match more narrowly). `hostcategory` is `all` and
    **cannot** be scoped further — extensively verified live (2026-08-28):
    neither an `ipaservers`-hostgroup reference nor a literal FQDN
    resolves for host-based sudo matching on this IPA/SSSD version, even
    with `sss_cache -R` + full `ipactl restart` + `ipa-compat-manage
    enable` (already active) — `getent netgroup ipaservers` returns
    nothing despite correct `nsswitch.conf`/`sssd.conf` config, a known
    upstream FreeIPA quirk affecting IPA *servers* resolving their own
    hostgroups as netgroups. Don't spend time re-attempting host-scoping
    without checking whether that upstream issue has since been fixed.
  - The account's Kerberos keys **must** be provisioned (`ipa user-mod
    svc-ansible --random`, or any password set) — an IPA user with none
    behaves oddly for authorization purposes even though SSH pubkey login
    (which never touches Kerberos) works fine regardless.
  - When diagnosing sudo-rule issues here again: `sudo -l -U <user>` (as
    root, querying *about* another user) is unreliable and gave false
    negatives multiple times during setup — trust `sudo -l`/an actual
    command run as the user themselves instead.
- The same workflow's `jetkvm-netbird-check` job is deliberately
  check-only (`--skip-tags update`, per `jetkvm-netbird-update.yml`'s own
  header) — JetKVM firmware swaps stay a manual decision, never
  auto-applied on a schedule. Don't change this job to actually apply
  updates without an explicit ask; it's reporting-only by design.

## Git / PRs

- This is a solo-maintainer repo (branch protection on `main` requires PRs
  and passing `lint` + `GitGuardian Security Checks`, but 0 approvals —
  merging your own PRs is normal here, not a gap).
- Squash-merge PRs (one commit per PR on `main`); this repo's history is
  linear by convention and branch protection now enforces it.
- Force-pushes and deletion of `main` are blocked, including for admins.

## Repo shape

Two independent halves deliberately kept in one repo (OpenTofu/AWS under
`environments/`, Ansible under `ansible/`) rather than split — GitHub
Actions already scopes secrets/permissions per-workflow and OIDC trust
conditions can be scoped per-environment, so splitting wouldn't add
isolation, just overhead. Revisit only if the Ansible side grows its own
distinct ownership/access model.
