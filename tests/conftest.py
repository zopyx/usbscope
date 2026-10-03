"""Shared fixtures: real OS payloads captured under ``tests/fixtures``."""

from __future__ import annotations

import json
import plistlib
from collections.abc import Sequence
from pathlib import Path

import pytest

from usbscope.models import Snapshot
from usbscope.snapshot import collect
from usbscope.sources import (
    ChargingSource,
    IoregSource,
    SystemProfiler,
    ThunderboltFabricSource,
    USBRegistrySource,
)
from usbscope.sources.shell import CommandResult

FIXTURES = Path(__file__).parent / "fixtures"

# The fixtures were captured on one machine: pin its identity so the suite does not
# depend on the host it runs on (the macOS version would otherwise come from CI).
FIXTURE_HOST = "mac"
FIXTURE_OS_VERSION = "27.0.1"

_PROFILER_FILES = {
    "SPUSBHostDataType": "usbhost.json",
    "SPUSBDataType": "usb_legacy_empty.json",
    "SPThunderboltDataType": "thunderbolt.json",
    "SPHardwareDataType": "hardware.json",
}

# The USB device tree issues one command; served from the captured IOUSB plane.
_REGISTRY_FILES = {
    "IOUSB": "usbplane.plist",
}

# The USB4/Thunderbolt fabric issues one command; served from the switch capture.
_FABRIC_FILES = {
    "IOThunderboltSwitch": "tb_switch.plist",
}

# The charging adapter issues two commands; both are served from the fixtures.
_CHARGING_FILES = {
    "SPPowerDataType": "power.json",
    "AppleSmartBattery": "battery.plist",
}


def fixture_bytes(name: str) -> bytes:
    """Return the raw bytes of a fixture file."""
    return (FIXTURES / name).read_bytes()


def fixture_json(name: str) -> dict[str, object]:
    """Return a fixture parsed as JSON."""
    return json.loads(fixture_bytes(name).decode("utf-8"))


def fixture_plist(name: str) -> dict[str, object]:
    """Return a fixture parsed as a plist."""
    return plistlib.loads(fixture_bytes(name))


def make_runner(files: dict[str, str]) -> object:
    """Build a command runner that serves fixtures keyed by the data type."""

    def runner(argv: Sequence[str]) -> CommandResult:
        for argument, filename in files.items():
            if argument in argv:
                return CommandResult(tuple(argv), 0, fixture_bytes(filename))
        return CommandResult(tuple(argv), 1, error=f"no fixture for {' '.join(argv)}")

    return runner


@pytest.fixture
def profiler() -> SystemProfiler:
    """SystemProfiler wired to the captured system_profiler payloads."""
    from typing import cast

    from usbscope.sources.profiler import Runner

    return SystemProfiler(runner=cast(Runner, make_runner(_PROFILER_FILES)))


@pytest.fixture
def ioreg() -> IoregSource:
    """IoregSource wired to the captured IOPort plist."""
    from typing import cast

    from usbscope.sources.ioreg import Runner

    return IoregSource(runner=cast(Runner, make_runner({"IOPort": "ioport.plist"})))


@pytest.fixture
def charging() -> ChargingSource:
    """ChargingSource wired to the captured battery/charger payloads."""
    from typing import cast

    from usbscope.sources.charging import Runner

    return ChargingSource(runner=cast(Runner, make_runner(_CHARGING_FILES)))


@pytest.fixture
def usbregistry() -> USBRegistrySource:
    """USBRegistrySource wired to the captured IOUSB plane."""
    from typing import cast

    from usbscope.sources.usbregistry import Runner

    return USBRegistrySource(runner=cast(Runner, make_runner(_REGISTRY_FILES)))


@pytest.fixture
def tb_fabric() -> ThunderboltFabricSource:
    """ThunderboltFabricSource wired to the captured IOThunderboltSwitch plist."""
    from typing import cast

    from usbscope.sources.thunderbolt import Runner

    return ThunderboltFabricSource(runner=cast(Runner, make_runner(_FABRIC_FILES)))


@pytest.fixture
def snapshot(
    profiler: SystemProfiler,
    ioreg: IoregSource,
    charging: ChargingSource,
    usbregistry: USBRegistrySource,
    tb_fabric: ThunderboltFabricSource,
) -> Snapshot:
    """A full snapshot built from the captured payloads."""
    return collect(
        profiler=profiler,
        ioreg=ioreg,
        charging=charging,
        usbregistry=usbregistry,
        fabric=tb_fabric,
        host=FIXTURE_HOST,
        os_version=FIXTURE_OS_VERSION,
    )
