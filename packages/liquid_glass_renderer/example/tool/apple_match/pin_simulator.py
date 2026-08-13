#!/usr/bin/env python3
"""Locate and boot the one simulator that captured the pinned references."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "compare"))

from apple_match.hotloop import (  # noqa: E402
    PINNED_DEVICE_UDID,
    ensure_pinned_simulator,
)


ensure_pinned_simulator(PINNED_DEVICE_UDID)
print(PINNED_DEVICE_UDID)
