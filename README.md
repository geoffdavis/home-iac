# home-iac

Infrastructure as code for the home lab: **OpenTofu** for AWS, and (as of
[#8][issue-8]) **Ansible** for the UniFi UDM Pro's DHCP/DNS config.
"home-iac" was already tool-agnostic before the Ansible half landed —
see section 6 of the "Agent Access and Deploy Coordination" note (in the
personal-notes vault) for why this repo, not a rename, absorbed it.

[issue-8]: https://github.com/geoffdavis/home-iac/issues/8

## What it manages

- **S3 buckets** for backups (Home Assistant, PostgreSQL)
- **IAM users and policies** for backup service accounts
- **State backend** (S3 bucket + DynamoDB lock table)
- **UDM Pro static DNS + DHCP fixed reservations**, synced one-way from
  NetBox (`ansible/roles/unifi_network_dns_record`,
  `ansible/roles/unifi_network_ip_reservation` — see
  [`docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md`][spec]).
  **NetBox itself doesn't exist yet** — hosting it is
  [nix-personal#542][np542], still in flight; these roles are written
  against NetBox's documented API contract and unit-tested, but have
  never run against a live instance. See each role's README for exact
  gaps.

[spec]: docs/superpowers/specs/2026-08-21-netbox-udm-sync-design.md
[np542]: https://github.com/geoffdavis/nix-personal/issues/542

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.5.0
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`)
- [Task](https://taskfile.dev/) runner
- [uv](https://docs.astral.sh/uv/) (Ansible + pytest dev tooling)
- AWS credentials stored in 1Password (Terraform half)
- UDM Pro + NetBox API credentials stored in 1Password (Ansible half —
  see the `unifi_network_*` role READMEs)

## Usage — Terraform (AWS)

```bash
cp .env.example .env   # edit with your 1Password item references
task init              # initialize OpenTofu
task plan              # preview changes
task apply             # apply changes
```

## Usage — Ansible (UDM sync)

```bash
uv sync --group dev                 # ansible-core, ansible-lint, pytest, ...
task ansible:collections            # install ansible-galaxy collections
task ansible:test                   # unit tests (filter-plugin + drift logic)
task ansible:check                  # syntax-check + ansible-lint
task ansible:sync                   # --check (dry-run) against the real UDM/NetBox
task ansible:sync FORCE=1           # apply for real
```

## Structure

```
environments/
  home/                # home lab environment
    backend.tf         # S3 remote state backend
    main.tf            # AWS provider + common tags
    versions.tf        # provider version constraints
    state-backend.tf   # state bucket + DynamoDB table resources
    s3-buckets.tf      # workload S3 buckets
    s3-iam-access.tf   # IAM users + policies for backup access
    variables.tf       # input variables
modules/
  s3-buckets/          # reusable S3 bucket module
ansible/
  ansible.cfg
  inventory.yml         # single localhost "host" — both roles delegate_to: localhost
  host_vars/localhost.yml
  collections/requirements.yml
  filter_plugins/netbox_sync.py   # NetBox<->UDM set-comparison + transform logic
  playbooks/unifi-network-netbox-sync.yml
  roles/
    unifi_network_dns_record/     # rewritten: NetBox-sourced static DNS
    unifi_network_ip_reservation/ # new: NetBox status=dhcp -> UDM DHCP reservations
  tests/                # pytest — filter-plugin unit tests + Templar-rendered drift tests
```

## State backend

State is stored in S3 (`opentofu-state-home-iac-<account-id>`) with DynamoDB locking.
If the state bucket is destroyed, bootstrap with local state first:

1. Temporarily switch `backend.tf` to `backend "local" {}`
2. `tofu init -reconfigure && tofu apply -target=aws_s3_bucket.terraform_state -target=aws_dynamodb_table.terraform_locks`
3. Restore the S3 backend config and `tofu init -migrate-state`
