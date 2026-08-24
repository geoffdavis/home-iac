#!/usr/bin/env python3
"""ipa-healthcheck -> node_exporter textfile metrics.

Installed by the freeipa_metrics role (ugreen-nas-compose); run by
ipa-healthcheck-metrics.timer. Emits severity counts, one bounded series
per non-SUCCESS check, and the minimum cert-days-remaining seen in any
check's kw (the classic silent IPA killer). Atomic tmp+rename write so
node_exporter never scrapes a partial file.
"""
import json
import os
import subprocess
import tempfile
import time

TEXTFILE_DIR = "/var/lib/node_exporter/textfile"
OUT = os.path.join(TEXTFILE_DIR, "ipa_healthcheck.prom")


def esc(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def main():
    start = time.time()
    proc = subprocess.run(
        ["ipa-healthcheck", "--output-type", "json"],
        capture_output=True,
        text=True,
        timeout=600,
    )
    lines = [
        "ipa_healthcheck_last_run_timestamp_seconds %d" % int(start),
        "ipa_healthcheck_exit_code %d" % proc.returncode,
    ]
    try:
        results = json.loads(proc.stdout)
        if not isinstance(results, list):
            raise ValueError("unexpected shape")
    except ValueError:
        results = None

    if results is None:
        lines.append("ipa_healthcheck_parse_ok 0")
    else:
        lines.append("ipa_healthcheck_parse_ok 1")
        sev_counts = {}
        cert_days = []
        for r in results:
            sev = str(r.get("result", "UNKNOWN"))
            sev_counts[sev] = sev_counts.get(sev, 0) + 1
            if sev != "SUCCESS":
                lines.append(
                    'ipa_healthcheck_failed{source="%s",check="%s",severity="%s"} 1'
                    % (esc(r.get("source", "")), esc(r.get("check", "")), sev)
                )
            kw = r.get("kw") or {}
            days = kw.get("days")
            if isinstance(days, int):
                cert_days.append(days)
        for sev in sorted(sev_counts):
            lines.append(
                'ipa_healthcheck_results_total{severity="%s"} %d'
                % (sev, sev_counts[sev])
            )
        if cert_days:
            lines.append("ipa_healthcheck_cert_days_min %d" % min(cert_days))
    lines.append(
        "ipa_healthcheck_duration_seconds %.1f" % (time.time() - start)
    )

    fd, tmp = tempfile.mkstemp(dir=TEXTFILE_DIR)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, OUT)


if __name__ == "__main__":
    main()
