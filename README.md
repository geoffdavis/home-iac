# home-iac

Infrastructure-as-code for the home lab: OpenTofu for AWS, and Ansible for
FreeIPA replica management, UniFi UDM network integration, and JetKVM
out-of-band console maintenance.

## What it manages

**OpenTofu (AWS):**

- **S3 buckets** for backups (Longhorn, Home Assistant, PostgreSQL)
- **IAM users and policies** for backup service accounts
- **State backend** — [OpenTaco Cloud](https://otaco.app); see
  [State backend](#state-backend) below
- **GitHub OIDC role for CI** — lets
  [Digger/OpenTaco](https://opentaco.dev) run plan/apply from GitHub
  Actions without static AWS keys; see [PR automation](#pr-automation)

**Ansible (FreeIPA + UniFi UDM):**

- **FreeIPA replica VM provisioning** (`nixos_freeipa_vm`) — builds the
  per-site `ipa-<site>` libvirt/KVM guest on its NixOS NAS host.
- **FreeIPA replica day-2 ops** — unattended security patching + staggered
  reboot (`freeipa_autopatch`), node_exporter + ipa-healthcheck metrics
  (`freeipa_metrics`), journald→fleet-syslog forwarding (`freeipa_rsyslog`).
- **UniFi UDM Pro network integration** — static DNS records
  (`unifi_network_dns_record`), DHCP PXE-boot options
  (`unifi_network_dhcp_pxe`), port forwarding
  (`unifi_network_port_forward`), all reconciled idempotently via the
  UDM's REST API.
- **JetKVM out-of-band console maintenance** — netbird updates on the
  per-site JetKVM consoles (`playbooks/jetkvm-netbird-update.yml`, the
  `oob_kvm` inventory group); see `docs/jetkvm-provisioning.md` for the
  bring-up procedure.
- **Scheduled reconciliation** — the FreeIPA day-2 ops and UniFi UDM sync
  above also run daily via `.github/workflows/ansible-reconcile.yml`, on a
  self-hosted runner with LAN access to those targets; see `AGENTS.md` for
  the credential/runner details.

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.5.0
- [Ansible](https://docs.ansible.com/) (`ansible-core` + the collections in
  `ansible/collections/requirements.yml`) for the FreeIPA/UDM half
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`)
- [Task](https://taskfile.dev/) runner
- AWS credentials stored in 1Password (OpenTofu); UDM + FreeIPA credentials
  in the `Automation` / `nas-overlay` 1Password vaults (Ansible)
- An [OpenTaco](https://otaco.app) account with access to this repo's
  workspace, logged in locally via `tofu login otaco.app`

## Usage

```bash
cp .env.example .env   # edit with your 1Password item references

# OpenTofu (AWS)
task init              # initialize OpenTofu
task plan              # preview changes
task apply             # apply changes

# Ansible (FreeIPA + UniFi UDM)
task ansible:install   # install the pinned collection dependencies
task ansible:check     # lint + syntax-check (static, no live connections)
task ansible:run -- playbooks/unifi-network.yml --check --diff  # dry run
task ansible:run -- playbooks/unifi-network.yml                 # real run
```

## Structure

```
digger.yml             # Digger/OpenTaco project config (see PR automation)
environments/
  home/                # home lab environment
    cloud.tf           # OpenTaco Cloud remote state backend
    github-oidc.tf     # GitHub OIDC provider/role for CI plan/apply
    main.tf            # AWS provider + common tags
    versions.tf        # provider version constraints
    state-backend.tf   # legacy state bucket + lock table (see State backend)
    s3-buckets.tf      # workload S3 buckets
    s3-iam-access.tf   # IAM users + policies for backup access
    variables.tf       # input variables
modules/
  s3-buckets/          # reusable S3 bucket module
ansible/
  roles/               # nixos_freeipa_vm, freeipa_autopatch, freeipa_metrics,
                        # freeipa_rsyslog, unifi_network_dns_record,
                        # unifi_network_dhcp_pxe, unifi_network_port_forward
  playbooks/           # entry points, one per role/role-group, plus
                        # jetkvm-netbird-update.yml
  inventory.yml        # nas_nixos + ipa_replicas + oob_kvm (+ site_* groups)
  host_vars/, group_vars/
docs/
  jetkvm-provisioning.md  # JetKVM OOB console bring-up procedure
```

## State backend

State lives in [OpenTaco Cloud](https://otaco.app) (`cloud.tf`), authenticated
via `tofu login otaco.app` — no AWS credentials needed just to run `tofu
init`/`plan`/`apply` against state itself.

`state-backend.tf`'s S3 bucket and DynamoDB table are a legacy backend, kept
as plain (no longer backend-wired) resources rather than destroyed.

To fall back to local state if the OpenTaco workspace is ever unreachable:

1. Comment out the `cloud` block in `cloud.tf`
2. `tofu init -migrate-state` (prompts to copy state to local)

## PR automation

[Digger](https://github.com/diggerhq/digger)/OpenTaco runs `tofu plan` on
PRs and `apply` on merge for the `environments/home` project, configured by:

- `digger.yml` — project definition (`dir: environments/home`,
  `opentofu: true`), auto-merge, and PR comment reporting
- `.github/workflows/digger_workflow.yml` — the `workflow_dispatch` job
  OpenTaco's GitHub App (already installed on this repo) dispatches with a
  computed `spec`
- `environments/home/github-oidc.tf` — the AWS side: an IAM OIDC provider +
  role scoped to just the resources this environment manages, assumed via
  `aws-role-to-assume` (no static `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
  secrets). The role ARN is set as the `AWS_DIGGER_ROLE_ARN` repo Actions
  variable.
