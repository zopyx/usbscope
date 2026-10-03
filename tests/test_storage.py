"""Tests for the USB mass-storage inventory (``usbscope.sources.storage``)."""

from __future__ import annotations

import plistlib
from typing import cast

from usbscope.sources.shell import CommandResult
from usbscope.sources.storage import (
    Runner,
    StorageDevice,
    StorageSource,
    format_bytes,
    parse_storage,
)


def _listing(*identifiers: str) -> dict[str, object]:
    return {"WholeDisks": list(identifiers), "AllDisksAndPartitions": []}


def _usb(**overrides: object) -> dict[str, object]:
    info: dict[str, object] = {
        "DeviceIdentifier": "disk4",
        "BusProtocol": "USB",
        "MediaName": "USB DISK 3.0",
        "VolumeName": "STICK",
        "TotalSize": 32_000_000_000,
        "Writable": True,
        "Removable": True,
        "MountPoint": "/Volumes/STICK",
        "Content": "DOS_FAT_32",
    }
    info.update(overrides)
    return info


def _internal() -> dict[str, object]:
    return {
        "DeviceIdentifier": "disk0",
        "BusProtocol": "Apple Fabric",
        "MediaName": "APPLE SSD AP1024Z",
        "TotalSize": 1_000_555_581_440,
        "Writable": True,
        "Removable": False,
    }


def test_only_usb_disks_are_kept() -> None:
    devices = parse_storage(_listing("disk0", "disk4"), {"disk0": _internal(), "disk4": _usb()})
    assert [device.identifier for device in devices] == ["disk4"]


def test_volume_name_wins_over_media_name() -> None:
    devices = parse_storage(_listing("disk4"), {"disk4": _usb()})
    assert devices[0].name == "STICK"
    assert devices[0].label == "STICK"


def test_a_disk_without_a_volume_name_falls_back_to_the_media_name() -> None:
    devices = parse_storage(_listing("disk4"), {"disk4": _usb(VolumeName="")})
    assert devices[0].name == "USB DISK 3.0"


def test_read_only_comes_from_writable() -> None:
    devices = parse_storage(_listing("disk4"), {"disk4": _usb(Writable=False)})
    assert devices[0].read_only is True


def test_read_only_falls_back_to_media_read_only() -> None:
    info = _usb(MediaReadOnly=True)
    del info["Writable"]
    devices = parse_storage(_listing("disk4"), {"disk4": info})
    assert devices[0].read_only is True


def test_capacity_prefers_total_size_then_size() -> None:
    devices = parse_storage(_listing("disk4"), {"disk4": _usb(TotalSize=None, Size=16_000_000_000)})
    assert devices[0].capacity_bytes == 16_000_000_000


def test_removable_falls_back_to_removable_media() -> None:
    info = _usb(RemovableMedia=True)
    del info["Removable"]
    devices = parse_storage(_listing("disk4"), {"disk4": info})
    assert devices[0].removable is True


def test_an_empty_mount_point_is_none() -> None:
    devices = parse_storage(_listing("disk4"), {"disk4": _usb(MountPoint="")})
    assert devices[0].mount_point is None


def test_a_disk_without_info_is_skipped() -> None:
    devices = parse_storage(_listing("disk4", "disk5"), {"disk5": _usb(DeviceIdentifier="disk5")})
    assert [device.identifier for device in devices] == ["disk5"]


def test_order_follows_the_disk_list() -> None:
    infos = {
        "disk4": _usb(DeviceIdentifier="disk4"),
        "disk5": _usb(DeviceIdentifier="disk5"),
    }
    devices = parse_storage(_listing("disk5", "disk4"), infos)
    assert [device.identifier for device in devices] == ["disk5", "disk4"]


def test_capacity_text_is_human_readable() -> None:
    assert format_bytes(32_000_000_000) == "32.0 GB"
    assert format_bytes(16_000_000) == "16 MB"
    assert format_bytes(4_000) == "4 kB"
    assert format_bytes(512) == "512 B"
    assert format_bytes(None) is None
    assert StorageDevice("disk4", capacity_bytes=32_000_000_000).capacity_text == "32.0 GB"


def _runner(listing: dict[str, object], infos: dict[str, dict[str, object]]) -> Runner:
    def run(argv: list[str]) -> CommandResult:
        if "list" in argv:
            return CommandResult(tuple(argv), 0, plistlib.dumps(listing))
        for identifier, info in infos.items():
            if "info" in argv and identifier in argv:
                return CommandResult(tuple(argv), 0, plistlib.dumps(info))
        return CommandResult(tuple(argv), 1, error="no fixture for " + " ".join(argv))

    return cast(Runner, run)


def test_the_source_serves_list_and_info() -> None:
    source = StorageSource(runner=_runner(_listing("disk4"), {"disk4": _usb()}))
    devices, warnings = source.inventory()
    assert [device.identifier for device in devices] == ["disk4"]
    assert warnings == ()


def test_a_machine_without_usb_storage_is_empty_not_an_error() -> None:
    source = StorageSource(runner=_runner(_listing("disk0"), {"disk0": _internal()}))
    devices, warnings = source.inventory()
    assert devices == ()
    assert warnings == ()


def test_a_failing_diskutil_is_an_empty_inventory_without_a_warning() -> None:
    def failing(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 127, error="diskutil not found")

    source = StorageSource(runner=cast(Runner, failing))
    devices, warnings = source.inventory()
    assert devices == ()
    assert warnings == ()


def test_unparsable_output_is_treated_as_absence() -> None:
    def garbage(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 0, b"not a plist")

    source = StorageSource(runner=cast(Runner, garbage))
    assert source.inventory() == ((), ())
