"""Tests for the aggregation layer (merging system_profiler and ioreg)."""

from __future__ import annotations

import platform
from typing import cast

import pytest

from usbscope.models import Snapshot
from usbscope.snapshot import collect
from usbscope.sources import IoregSource, SystemProfiler
from usbscope.sources.profiler import Runner as ProfilerRunner
from usbscope.sources.shell import CommandResult

from .conftest import make_runner


def test_snapshot_from_captures(snapshot: Snapshot) -> None:
    assert snapshot.warnings == ()
    assert snapshot.model == "MacBook Pro"
    assert snapshot.chip == "Apple M3 Pro"
    assert len(snapshot.ports) == 6
    assert len(snapshot.connected_ports) == 2
    assert snapshot.emarked_cables == ()
    assert len(snapshot.thunderbolt) == 3
    assert len(snapshot.devices) == 1


def test_device_is_enriched_across_sources(snapshot: Snapshot) -> None:
    """ioreg knows the port, system_profiler knows the identity - both must survive."""
    device = snapshot.devices[0]
    assert device.name == "YubiKey OTP+FIDO+CCID"
    assert device.port == "USB-C@3"  # from ioreg
    assert device.transport == "USB2"  # from ioreg
    assert device.bus == "USB 3.1 Bus"  # from system_profiler
    assert device.source == "system_profiler"


def test_ports_without_bus_entry_get_their_own_branch(ioreg: IoregSource) -> None:
    """A device the bus report lost still shows up, on a synthetic bus."""
    empty_host = {"SPUSBHostDataType": "empty_usb.json"}
    profiler = SystemProfiler(runner=cast(ProfilerRunner, make_runner(empty_host)))
    snapshot = collect(profiler=profiler, ioreg=ioreg)
    assert len(snapshot.buses) == 1
    bus = snapshot.buses[0]
    assert bus.name.startswith("Port controller only")
    assert [device.name for device in bus.devices] == ["YubiKey OTP+FIDO+CCID"]
    assert len(snapshot.devices) == 1  # still deduplicated by location ID


def test_broken_source_degrades_gracefully() -> None:
    def failing(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 127, error="system_profiler not found")

    from usbscope.sources.ioreg import Runner as IoregRunner

    snapshot = collect(
        profiler=SystemProfiler(runner=failing),
        ioreg=IoregSource(runner=cast(IoregRunner, make_runner({"IOPort": "ioport.plist"}))),
    )
    assert snapshot.warnings
    assert snapshot.ports  # ioreg data still made it through
    assert len(snapshot.buses) == 1  # only the synthetic port-only branch
    assert snapshot.buses[0].name.startswith("Port controller only")
    assert snapshot.devices  # port-only devices are kept


def test_clock_is_injectable(ioreg: IoregSource, profiler: SystemProfiler) -> None:
    from datetime import datetime

    fixed = datetime(2026, 10, 2, 12, 0, 0)
    snapshot = collect(profiler=profiler, ioreg=ioreg, clock=lambda: fixed)
    assert snapshot.seen_at == fixed


def test_host_identity_is_injectable(
    profiler: SystemProfiler, ioreg: IoregSource, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The captured fixtures must describe one machine, whoever runs the suite.

    Without the injection the macOS version came from the host, so the suite passed
    on the capture machine and failed on a runner (macOS 14 vs 27) for assertions
    that only looked like fixture data.
    """
    from .conftest import FIXTURE_HOST, FIXTURE_OS_VERSION

    monkeypatch.setattr(platform, "mac_ver", lambda: ("14.8.9", (), ""))

    pinned = collect(
        profiler=profiler,
        ioreg=ioreg,
        host=FIXTURE_HOST,
        os_version=FIXTURE_OS_VERSION,
    )
    assert pinned.os_version == FIXTURE_OS_VERSION
    assert pinned.host == FIXTURE_HOST

    live = collect(profiler=profiler, ioreg=ioreg)
    assert live.os_version == "14.8.9"  # the host is the default, not the fixture
