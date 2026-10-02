"""Tests for the system_profiler adapter against real captured payloads."""

from __future__ import annotations

from typing import cast

import pytest

from tests.conftest import make_runner
from usbscope.models import UsbMode
from usbscope.sources.profiler import Runner, SystemProfiler
from usbscope.sources.shell import CommandResult


def test_usb_buses_from_real_capture(profiler: SystemProfiler) -> None:
    buses, warnings = profiler.usb_buses()
    assert warnings == ()
    assert len(buses) == 3
    assert {bus.driver for bus in buses} == {"AppleT8122USBXHCI"}
    assert {bus.location_id for bus in buses} == {0x02000000, 0x00000000, 0x01000000}
    devices = [device for bus in buses for device in bus.devices]
    assert len(devices) == 1
    yubikey = devices[0]
    assert yubikey.name == "YubiKey OTP+FIDO+CCID"
    assert yubikey.vendor == "Yubico"
    assert (yubikey.vendor_id, yubikey.product_id) == (0x1050, 0x0407)
    assert yubikey.location_id == 0x01100000
    assert yubikey.speed_mbps == 12
    assert yubikey.mode is UsbMode.FULL_SPEED
    assert yubikey.serial is None  # reported as "Not Provided" by macOS
    assert yubikey.connection == "Removable"


def test_legacy_parser_falls_back(profiler: SystemProfiler) -> None:
    """The legacy data type is empty on this Mac, so the host data type wins."""
    buses, _warnings = profiler.usb_buses()
    assert len(buses) == 3


def test_legacy_key_names_are_supported() -> None:
    """The legacy key style is pinned with a synthetic payload (see fixtures/README)."""
    runner = cast(Runner, make_runner({"SPUSBDataType": "usb_legacy_synthetic.json"}))
    profiler = SystemProfiler(runner=runner)
    buses, _warnings = profiler.usb_buses()
    assert len(buses) == 1
    devices = buses[0].devices
    # the keyboard sits behind a hub, so the walk has to descend into it
    assert [device.name for device in devices] == ["USB 3.1 Bus", "USB Keyboard"]
    keyboard = devices[-1]
    assert (keyboard.vendor_id, keyboard.product_id) == (0x046D, 0xC31C)
    assert keyboard.vendor == "Logitech"
    assert keyboard.serial == "ABC123"
    assert keyboard.mode is UsbMode.LOW_SPEED  # 1.5 Mb/s


def test_thunderbolt_receptacles(profiler: SystemProfiler) -> None:
    ports, warnings = profiler.thunderbolt()
    assert warnings == ()
    assert len(ports) == 3
    assert {port.receptacle for port in ports} == {1, 2, 3}
    assert {port.speed for port in ports} == {"Up to 40 Gb/s"}
    assert not any(port.connected for port in ports)
    assert ports[0].device == "MacBook Pro"


def test_hardware_facts(profiler: SystemProfiler) -> None:
    hardware, warnings = profiler.hardware()
    assert warnings == ()
    assert hardware["model"] == "MacBook Pro"
    assert hardware["chip"] == "Apple M3 Pro"


def test_broken_command_is_reported_not_raised() -> None:
    def failing(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 1, error="boom")

    profiler = SystemProfiler(runner=failing)
    buses, warnings = profiler.usb_buses()
    assert buses == ()
    assert warnings == ("boom",)


def test_unparsable_output_is_reported() -> None:
    def broken(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 0, b"not json at all")

    _buses, warnings = SystemProfiler(runner=broken).usb_buses()
    assert warnings and "unparsable" in warnings[0]


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("0x01100000", 0x01100000),
        ("0x05ac (Apple Inc.)", 0x05AC),
        ("Not Provided", None),
        (None, None),
    ],
)
def test_integer_coercion(raw: str | None, expected: int | None) -> None:
    from usbscope.sources.profiler import _to_int

    assert _to_int(raw) == expected
