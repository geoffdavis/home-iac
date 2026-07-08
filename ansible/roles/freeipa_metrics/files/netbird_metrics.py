#!/usr/bin/env python3
"""netbird status -> node_exporter textfile metrics.

Installed by the freeipa_metrics role (ugreen-nas-compose); run by
netbird-metrics.timer. Mirrors the NAS-side exporter (nix-personal
modules/nas/metrics.nix) metric-for-metric so the Grafana host/IPA
detail dashboards read one uniform netbird signal across the fleet:

  netbird_up                     daemon running and answered `status --json`
  netbird_management_connected   management server session up
  netbird_signal_connected       signal server session up
  netbird_peers_total            peers in the overlay
  netbird_peers_connected        peers currently connected

The dead-man heartbeat only proves "host has SOME route out"; this
distinguishes "WAN up but overlay down" — exactly the state that makes
a replica unreachable for scrapes and SSH. Atomic tmp+rename write so
node_exporter never scrapes a partial file.
"""
import json
import os
import subprocess
import tempfile

TEXTFILE_DIR = "/var/lib/node_exporter/textfile"
OUT = os.path.join(TEXTFILE_DIR, "netbird.prom")


DOWN = [
    "netbird_up 0",
    "netbird_management_connected 0",
    "netbird_signal_connected 0",
    "netbird_peers_total 0",
    "netbird_peers_connected 0",
]


def as_flag(value):
    return 1 if value is True else 0


def collect():
    try:
        proc = subprocess.run(
            ["netbird", "status", "--json"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        status = json.loads(proc.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return DOWN
    if proc.returncode != 0 or not isinstance(status, dict):
        return DOWN

    # Key names moved between netbird releases (management -> managementState
    # etc.) — accept either, like the NAS-side jq does.
    management = status.get("management") or status.get("managementState") or {}
    signal = status.get("signal") or status.get("signalState") or {}
    peers = status.get("peers") or {}
    return [
        "netbird_up 1",
        "netbird_management_connected %d" % as_flag(management.get("connected")),
        "netbird_signal_connected %d" % as_flag(signal.get("connected")),
        "netbird_peers_total %d" % (peers.get("total") or 0),
        "netbird_peers_connected %d" % (peers.get("connected") or 0),
    ]


def main():
    fd, tmp = tempfile.mkstemp(dir=TEXTFILE_DIR)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(collect()) + "\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, OUT)


if __name__ == "__main__":
    main()
