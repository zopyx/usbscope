#!/usr/bin/env python3
"""Regenerate the Swift parity golden from the fixtures.

The Swift port is verified against the *very same* fixtures the Python suite
uses (``tests/fixtures``). This script serialises a snapshot built from them
with the Python implementation and writes the result to
``SwiftTests/Golden/snapshot.json``; ``swift test`` compares the Swift
implementation's JSON against that file. Regenerate it whenever a fixture (or
the serialiser) changes, so the two implementations cannot drift apart
unnoticed:

    uv run python scripts/swift_golden.py
"""

from __future__ import annotations

import json
from collections.abc import Callable, Sequence
from datetime import datetime
from pathlib import Path
from typing import Any

from usbscope.serialize import snapshot_to_dict
from usbscope.snapshot import collect
from usbscope.sources import (
    ChargingSource,
    IoregSource,
    SystemProfiler,
    ThunderboltFabricSource,
    USBRegistrySource,
)
from usbscope.sources.shell import CommandResult

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
GOLDEN = ROOT / "SwiftTests" / "Golden" / "snapshot.json"

# Must match `SwiftTests/Fixtures.swift` and `tests/conftest.py`.
HOST = "mac"
OS_VERSION = "27.0.1"
SEEN_AT = datetime(2026, 10, 2, 12, 0, 0)

PROFILER_FILES = {
    "SPUSBHostDataType": "usbhost.json",
    "SPUSBDataType": "usb_legacy_empty.json",
    "SPThunderboltDataType": "thunderbolt.json",
    "SPHardwareDataType": "hardware.json",
}
CHARGING_FILES = {
    "SPPowerDataType": "power.json",
    "AppleSmartBattery": "battery.plist",
}
REGISTRY_FILES = {
    "IOUSB": "usbplane.plist",
}
FABRIC_FILES = {
    "IOThunderboltSwitch": "tb_switch.plist",
}


def _runner(files: dict[str, str]) -> Callable[[Sequence[str]], CommandResult]:
    """Serve a fixture per data type, like `make_runner` in tests/conftest.py."""

    def runner(argv: Sequence[str]) -> CommandResult:
        for argument, filename in files.items():
            if argument in argv:
                return CommandResult(tuple(argv), 0, (FIXTURES / filename).read_bytes())
        return CommandResult(tuple(argv), 1, error=f"no fixture for {' '.join(argv)}")

    return runner


def build() -> dict[str, Any]:
    """The same snapshot the Swift suite builds, serialised by Python."""
    return snapshot_to_dict(
        collect(
            profiler=SystemProfiler(runner=_runner(PROFILER_FILES)),
            ioreg=IoregSource(runner=_runner({"IOPort": "ioport.plist"})),
            charging=ChargingSource(runner=_runner(CHARGING_FILES)),
            usbregistry=USBRegistrySource(runner=_runner(REGISTRY_FILES)),
            fabric=ThunderboltFabricSource(runner=_runner(FABRIC_FILES)),
            host=HOST,
            os_version=OS_VERSION,
            clock=lambda: SEEN_AT,
        )
    )


def main() -> int:
    payload = build()
    GOLDEN.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {GOLDEN.relative_to(ROOT)} "
        f"({len(payload['ports'])} ports, {len(payload['buses'])} buses, "
        f"{len(payload['thunderbolt'])} thunderbolt)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
