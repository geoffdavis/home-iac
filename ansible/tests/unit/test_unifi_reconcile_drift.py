"""Unit tests for unifi_network_dns_record's reconcile drift logic.

Renders the REAL Jinja expression out of reconcile_one.yml with
ansible's own Templar, not a copy — so template edits are exercised
directly, not just a hand-maintained mirror that could silently drift
from the actual task file.

reconcile_one.yml itself is UNCHANGED from the ugreen-nas-compose
original (design doc: "UDM-side diff/PUT logic unchanged") — these are
the same regression guard that role always needed, just pointed at
this repo's copy.
"""

from pathlib import Path

import pytest
import yaml
from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar, trust_as_template

ROLES = Path(__file__).resolve().parents[2] / "roles"


def _load_tasks(role: str) -> list[dict]:
    return yaml.safe_load((ROLES / role / "tasks" / "reconcile_one.yml").read_text())


def _find_task(tasks: list[dict], name_prefix: str) -> dict:
    matches = [t for t in tasks if t.get("name", "").startswith(name_prefix)]
    assert matches, f"no task named {name_prefix!r}*"
    return matches[0]


def _drift_expr(role: str, fact_name: str) -> str:
    task = _find_task(_load_tasks(role), "Compute drift")
    return task["ansible.builtin.set_fact"][fact_name]


def _render(expr: str, variables: dict):
    templar = Templar(loader=DataLoader(), variables=variables)
    return templar.template(trust_as_template(expr))


DNS_DESIRED = {
    "record_type": "CNAME",
    "key": "syslog.home.geoffdavis.com",
    "value": "nas-sdg.iot.home.geoffdavis.com",
    "enabled": True,
}
DNS_SERVER_EXTRAS = {"_id": "665f00", "site_id": "abc123", "ttl": 0}


def _dns_drift(match: list, desired: dict = DNS_DESIRED, state: str = "present"):
    return _render(
        _drift_expr("unifi_network_dns_record", "_udm_dns_needs_update"),
        {
            "_udm_dns_match": match,
            "_udm_dns_desired": desired,
            "_udm_dns_record": {"state": state},
        },
    )


def test_dns_no_match_is_not_drift():
    assert _dns_drift([]) is False


def test_dns_exact_match_with_server_extras_is_not_drift():
    assert _dns_drift([DNS_DESIRED | DNS_SERVER_EXTRAS]) is False


def test_dns_value_drift_detected():
    current = DNS_DESIRED | DNS_SERVER_EXTRAS | {"value": "old-target.example.com"}
    assert _dns_drift([current]) is True


def test_dns_enabled_drift_detected():
    current = DNS_DESIRED | DNS_SERVER_EXTRAS | {"enabled": False}
    assert _dns_drift([current]) is True


def test_dns_absent_item_is_never_drift():
    current = DNS_DESIRED | DNS_SERVER_EXTRAS | {"value": "old-target.example.com"}
    assert _dns_drift([current], state="absent") is False


@pytest.mark.parametrize("verb", ["POST", "PUT", "DELETE"])
def test_dns_mutation_tasks_report_changed(verb: str):
    task = _find_task(_load_tasks("unifi_network_dns_record"), verb)
    assert task.get("changed_when") is True
