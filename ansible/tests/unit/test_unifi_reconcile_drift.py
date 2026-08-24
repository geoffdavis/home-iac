"""Unit tests for the UDM reconcile drift logic (unifi_network_dns_record +
unifi_network_ip_reservation).

Same technique as the ugreen-nas-compose original this role was
rewritten from: render the REAL Jinja expressions out of each role's
reconcile_one.yml with ansible's own Templar, not copies, so template
edits are exercised directly.

unifi_network_dns_record's reconcile_one.yml is UNCHANGED from the
ugreen-nas-compose original (design doc: "UDM-side diff/PUT logic
unchanged") — these tests are the same regression guard, ported.
unifi_network_ip_reservation's reconcile_one.yml is new, following the
same "project owned keys down and compare" pattern.
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


# ── unifi_network_dns_record (unchanged from ugreen-nas-compose) ───────

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


# ── unifi_network_ip_reservation (new role) ─────────────────────────────

RES_DESIRED = {
    "mac": "aa:bb:cc:dd:ee:ff",
    "use_fixedip": True,
    "fixed_ip": "172.29.10.31",
    "network_id": "665f10",
}
RES_SERVER_EXTRAS = {"_id": "665f20", "site_id": "abc123", "name": "pacificbeach", "hostname": "pacificbeach"}


def _res_drift(match: list, desired: dict = RES_DESIRED):
    return _render(
        _drift_expr("unifi_network_ip_reservation", "_udm_res_needs_update"),
        {
            "_udm_res_match": match,
            "_udm_res_desired": desired,
        },
    )


def test_res_no_match_is_not_drift():
    assert _res_drift([]) is False


def test_res_exact_match_with_server_extras_is_not_drift():
    """Server-side / discovered fields (_id, name, hostname) must not
    read as drift — this role only owns use_fixedip/fixed_ip/network_id
    and must never fight the controller over a device's discovered
    name."""
    assert _res_drift([RES_DESIRED | RES_SERVER_EXTRAS]) is False


def test_res_fixed_ip_drift_detected():
    current = RES_DESIRED | RES_SERVER_EXTRAS | {"fixed_ip": "172.29.10.99"}
    assert _res_drift([current]) is True


def test_res_network_id_drift_detected():
    current = RES_DESIRED | RES_SERVER_EXTRAS | {"network_id": "different-network"}
    assert _res_drift([current]) is True


def test_res_use_fixedip_false_is_drift():
    current = RES_DESIRED | RES_SERVER_EXTRAS | {"use_fixedip": False}
    assert _res_drift([current]) is True


@pytest.mark.parametrize("verb", ["POST", "PUT"])
def test_res_mutation_tasks_report_changed(verb: str):
    task = _find_task(_load_tasks("unifi_network_ip_reservation"), verb)
    assert task.get("changed_when") is True
