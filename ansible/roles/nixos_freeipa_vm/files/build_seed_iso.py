#!/usr/bin/env python3
"""Build a cloud-init NoCloud seed ISO on the Ansible controller.

libvirt VMs take cloud-init from a CDROM-attached NoCloud ISO. Rather than
require ISO-creation tooling (genisoimage / mkisofs / xorriso) on every
target host, we build the ISO on the controller with pycdlib (pure Python)
and copy it over.

Stdin protocol (JSON, single line OK or pretty-printed):

    {
      "out_path":  "/tmp/freeipa-vm-seed-ipa-sdg-1747623456.iso",
      "user_data": "#cloud-config\\nhostname: ipa-sdg.ipa.geoffdavis.com\\n...",
      "meta_data": "instance-id: ipa-sdg\\nlocal-hostname: ipa-sdg.ipa.geoffdavis.com\\n"
    }

NoCloud datasource semantics (cloud-init docs):
  - volume id MUST be `cidata`
  - filesystem contains files literally named `user-data` and `meta-data`
    at the volume root, plus an optional `network-config`
  - any ISO9660 / vfat filesystem with those files satisfies the datasource

We use ISO9660 level 3 + Joliet + Rock Ridge for max compatibility (Joliet
gives Windows-style long filenames, Rock Ridge gives POSIX semantics, level 3
allows files > 4 GiB which we'll never need but is the modern default).

The user_data field contains the netbird setup key in plaintext — this script
NEVER logs user_data and NEVER echoes stdin. The caller (the role's
provision_vm.yml block/always) is responsible for deleting the output ISO
after the VM is created.
"""
import json
import os
import sys

import pycdlib


def main() -> int:
    payload = json.load(sys.stdin)
    out_path: str = payload["out_path"]
    user_data: bytes = payload["user_data"].encode("utf-8")
    meta_data: bytes = payload["meta_data"].encode("utf-8")

    # Ensure parent dir exists (caller normally pre-creates /tmp).
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)

    iso = pycdlib.PyCdlib()
    # interchange_level=3: ISO9660 level 3 (large files OK)
    # joliet=3:            Joliet escape sequence 3 (max compatibility)
    # rock_ridge="1.09":   Rock Ridge POSIX extensions
    # vol_ident="cidata":  NoCloud datasource scans removable devices for this label
    iso.new(
        interchange_level=3,
        joliet=3,
        rock_ridge="1.09",
        vol_ident="cidata",
    )

    # add_fp adds a file from an in-memory fp + length. Paths:
    #   iso_path:    primary ISO9660 path (UPPERCASE, 8.3-ish — uses ;1 version suffix)
    #   joliet_path: Joliet path (case-preserved)
    #   rr_name:     Rock Ridge name (case-preserved)
    # cloud-init reads via the Rock Ridge or Joliet layer, so the lowercase
    # `user-data` / `meta-data` names must be present in BOTH.
    import io

    iso.add_fp(
        io.BytesIO(user_data),
        len(user_data),
        iso_path="/USERDATA.;1",
        joliet_path="/user-data",
        rr_name="user-data",
    )
    iso.add_fp(
        io.BytesIO(meta_data),
        len(meta_data),
        iso_path="/METADATA.;1",
        joliet_path="/meta-data",
        rr_name="meta-data",
    )

    iso.write(out_path)
    iso.close()
    # Tight mode: ISO bytes contain the setup key, owner-only read.
    os.chmod(out_path, 0o600)
    # Don't print the path — it's already known to the caller and stdout
    # can leak into ansible logs. Just exit 0.
    return 0


if __name__ == "__main__":
    sys.exit(main())
