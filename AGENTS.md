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
