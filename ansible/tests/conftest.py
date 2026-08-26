"""Test config for the ansible-side unit tests.

Puts ansible/ on sys.path so tests can import filter_plugins/netbox_sync
directly, and can resolve repo-relative role paths.
"""

import sys
from pathlib import Path

ANSIBLE_DIR = Path(__file__).resolve().parents[1]

if str(ANSIBLE_DIR) not in sys.path:
    sys.path.insert(0, str(ANSIBLE_DIR))
