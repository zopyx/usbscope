"""Tests for the USB device tree adapter (``ioreg -p IOUSB``)."""

from __future__ import annotations

from typing import cast

from usbscope.models import Snapshot
from usbscope.sources.shell import CommandResult
from usbscope.sources.usbregistry import (
    USB_CLASS_NAMES,
    Runner,
    USBRegistrySource,
    class_name,
    format_bcd_usb,
    parse_usb_devices,
    speed_code_name,
)

from .conftest import fixture_plist, make_runner


def test_class_names_cover_the_usb_if_base_classes() -> None:
    assert class_name(0) == "per-interface"
    assert class_name(3) == "HID"
    assert class_name(8) == "mass storage"
    assert class_name(9) == "hub"
    assert class_name(0xFF) == "vendor specific"
    assert class_name(0x42) == "0x42"  # unknown stays explicit
    assert class_name(None) is None
    assert len(USB_CLASS_NAMES) >= 20


def test_bcd_usb_is_rendered_as_the_specification_version() -> None:
    assert format_bcd_usb(512) == "2.00"  # 0x0200
    assert format_bcd_usb(528) == "2.10"  # 0x0210
    assert format_bcd_usb(768) == "3.00"  # 0x0300
    assert format_bcd_usb(0) is None
    assert format_bcd_usb(None) is None


def test_speed_codes() -> None:
    assert speed_code_name(1) == "full_speed"
    assert speed_code_name(3) == "super_speed"
    assert speed_code_name(9) == "code 9"
    assert speed_code_name(None) is None


def test_parse_the_captured_usb_plane() -> None:
    devices = parse_usb_devices(fixture_plist("usbplane.plist"))
    assert len(devices) == 1
    yubikey = devices[0]
    assert yubikey.name == "YubiKey OTP+FIDO+CCID"
    assert yubikey.vendor == "Yubico"
    assert yubikey.vendor_id == 0x1050
    assert yubikey.product_id == 0x0407
    assert yubikey.location_id == 0x01100000
    assert yubikey.device_class == 0
    assert yubikey.class_text == "per-interface"
    assert yubikey.bcd_usb == "2.00"
    assert yubikey.max_packet_size0 == 64
    assert yubikey.num_configurations == 1
    assert yubikey.speed_code == 1
    assert yubikey.speed_mbps == 12
    assert yubikey.tier == 1
    assert yubikey.parent is None
    assert yubikey.address == 1
    assert yubikey.source == "ioreg-usb"


def test_parse_a_hub_chain_sets_the_tier_and_the_parent() -> None:
    devices = {
        device.name: device
        for device in parse_usb_devices(fixture_plist("usbplane_hub_synthetic.plist"))
    }
    assert set(devices) == {"USB3.0 Hub", "USB Keyboard", "USB Flash Drive"}

    hub = devices["USB3.0 Hub"]
    assert hub.tier == 1
    assert hub.parent is None
    assert hub.device_class == 9
    assert hub.class_text == "hub (9/0/1)"

    keyboard = devices["USB Keyboard"]
    assert keyboard.tier == 2
    assert keyboard.parent == "USB3.0 Hub"
    assert keyboard.class_text == "HID (3/1/1)"

    drive = devices["USB Flash Drive"]
    assert drive.tier == 2
    assert drive.parent == "USB3.0 Hub"
    assert drive.class_text == "mass storage (8/6/80)"
    assert drive.speed_mbps == 5000


def test_source_serves_the_fixture_and_reports_no_warning() -> None:
    source = USBRegistrySource(runner=cast(Runner, make_runner({"IOUSB": "usbplane.plist"})))
    devices, warnings = source.devices()
    assert len(devices) == 1
    assert warnings == ()


def test_a_failing_command_is_a_warning_not_a_crash() -> None:
    def failing(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 1, error="ioreg not found")

    source = USBRegistrySource(runner=cast(Runner, failing))
    devices, warnings = source.devices()
    assert devices == ()
    assert warnings == ("ioreg not found",)


def test_devices_are_merged_into_the_snapshot(snapshot: Snapshot) -> None:
    """The snapshot carries the descriptor facts on the merged device."""
    device = next(item for item in snapshot.devices if item.name.startswith("YubiKey"))
    assert device.class_text == "per-interface"
    assert device.bcd_usb == "2.00"
    assert device.tier == 1
    assert device.address == 1
    assert device.num_configurations == 1
