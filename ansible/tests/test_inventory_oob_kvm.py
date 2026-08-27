"""Verify inventory.yml + group_vars/oob_kvm.yml shape for the JetKVM consoles.

Nothing else in the repo catches an inventory typo for these hosts: the
netbird-update play is fully group-driven, and a misspelled member simply
never gets converged — silently. These assertions are the only guard.
"""
from pathlib import Path
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
INVENTORY = REPO_ROOT / "ansible" / "inventory.yml"
GROUP_VARS = REPO_ROOT / "ansible" / "group_vars" / "oob_kvm.yml"

EXPECTED_CONSOLES = {
    "jetkvm-sdg-01",
    "jetkvm-sdg-02",
    "jetkvm-sct-01",
    "jetkvm-cin-01",
}


def _load_inventory() -> dict:
    return yaml.safe_load(INVENTORY.read_text())


def test_oob_kvm_group_declared():
    inv = _load_inventory()
    assert "oob_kvm" in inv["all"]["children"], "oob_kvm group must exist in inventory"


def test_oob_kvm_membership():
    inv = _load_inventory()
    hosts = inv["all"]["children"]["oob_kvm"]["hosts"]
    assert set(hosts.keys()) == EXPECTED_CONSOLES


def test_oob_kvm_hosts_use_netbird_fqdn():
    """hostname == netbird peer name == DNS label is a fleet-wide invariant;
    the device's own hostname is set to match at provisioning time."""
    inv = _load_inventory()
    hosts = inv["all"]["children"]["oob_kvm"]["hosts"]
    for name, cfg in hosts.items():
        assert cfg["ansible_host"] == f"{name}.netbird.cloud", (
            f"{name}.ansible_host should be {name}.netbird.cloud"
        )


def test_every_console_is_in_its_site_group():
    """A console outside its site_<code> group misses the site-wide silence
    that `nas-maintenance.sh` builds from the site suffix, so taking its NAS
    down would page for the KVM."""
    inv = _load_inventory()
    children = inv["all"]["children"]
    for name in EXPECTED_CONSOLES:
        site = name.split("-")[1]
        site_group = f"site_{site}"
        assert site_group in children, f"{site_group} must exist for {name}"
        assert name in children[site_group]["hosts"], (
            f"{name} must be listed under {site_group}"
        )


def test_oob_kvm_group_vars_connect_as_root():
    """Dropbear on these devices only offers root; there is no service user."""
    gv = yaml.safe_load(GROUP_VARS.read_text())
    assert gv.get("ansible_user") == "root"
