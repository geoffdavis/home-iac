# home-iac

Infrastructure-as-code for the home lab: OpenTofu (Terraform) for AWS, and
(since the migration in
[docs/superpowers/plans/2026-08-21-netbox-udm-sync.md](docs/superpowers/plans/2026-08-21-netbox-udm-sync.md))
Ansible for FreeIPA replica management, UniFi UDM network integration, and
JetKVM out-of-band console maintenance. The Ansible half moved here from
`ugreen-nas-compose`, which is being retired — see that plan's Task 1, and
issue #24 for the JetKVM tooling, for the migration details.

## What it manages

**OpenTofu (AWS):**

- **S3 buckets** for backups (Longhorn, Home Assistant, PostgreSQL)
- **IAM users and policies** for backup service accounts
- **State backend** (S3 bucket + DynamoDB lock table)

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

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.5.0
- [Ansible](https://docs.ansible.com/) (`ansible-core` + the collections in
  `ansible/collections/requirements.yml`) for the FreeIPA/UDM half
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`)
- [Task](https://taskfile.dev/) runner
- AWS credentials stored in 1Password (OpenTofu); UDM + FreeIPA credentials
  in the `Automation` / `nas-overlay` 1Password vaults (Ansible)

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

State is stored in S3 (`opentofu-state-home-iac-<account-id>`) with DynamoDB locking.
If the state bucket is destroyed, bootstrap with local state first:

1. Temporarily switch `backend.tf` to `backend "local" {}`
2. `tofu init -reconfigure && tofu apply -target=aws_s3_bucket.terraform_state -target=aws_dynamodb_table.terraform_locks`
3. Restore the S3 backend config and `tofu init -migrate-state`
