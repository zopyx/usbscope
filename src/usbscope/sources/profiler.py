"""Adapter for ``system_profiler``: buses, devices and Thunderbolt receptacles."""

from __future__ import annotations

import json
import plistlib
from collections.abc import Callable, Iterator
from typing import Any

from ..models import Bus, ThunderboltPort, UsbDevice
from .shell import CommandResult, run_command, system_binary

__all__ = ["SystemProfiler"]

Runner = Callable[[list[str]], CommandResult]

SYSTEM_PROFILER = system_binary(
    "system_profiler", "/usr/sbin/system_profiler", "/usr/bin/system_profiler"
)

# Keys used by the modern "SPUSBHostDataType" JSON output.
_HOST_KEYS = {
    "vendor_id": "USBDeviceKeyVendorID",
    "product_id": "USBDeviceKeyProductID",
    "vendor": "USBDeviceKeyVendorName",
    "serial": "USBDeviceKeySerialNumber",
    "version": "USBDeviceKeyProductVersion",
    "location": "USBKeyLocationID",
    "speed": "USBDeviceKeyLinkSpeed",
    "connection": "USBKeyHardwareType",
}

# Keys used by the legacy "SPUSBDataType" JSON output (Intel Macs, older macOS).
_LEGACY_KEYS = {
    "vendor_id": "vendor_id",
    "product_id": "product_id",
    "vendor": "manufacturer",
    "serial": "serial_num",
    "version": "bcd_device",
    "location": "location_id",
    "speed": "device_speed",
    "connection": "host_info",  # not reported; kept explicit
}


def _iter_nodes(node: Any) -> Iterator[dict[str, Any]]:
    """Depth first walk over the ``_items`` tree of a system_profiler report."""
    if not isinstance(node, dict):
        return
    yield node
    children = node.get("_items")
    if isinstance(children, list):
        for child in children:
            yield from _iter_nodes(child)


def _first(node: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if (value := node.get(key)) is not None:
            return value
    return None


def _looks_like_device(node: dict[str, Any], *, keys: dict[str, str]) -> bool:
    """True when a node of the report carries device identity, not bus data."""
    markers = (keys["product_id"], keys["vendor_id"], "idProduct", "idVendor")
    return any(node.get(marker) is not None for marker in markers)


def _to_int(value: Any) -> int | None:
    """Parse decimal, ``0x…`` and ``0x… (decimal)`` style integers."""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if not text or text.lower() in {"not provided", "n/a", "none"}:
        return None
    head = text.split()[0].rstrip(",")
    try:
        return int(head, 16) if head.lower().startswith("0x") else int(head, 10)
    except ValueError:
        return None


def _speed_mbps(value: Any) -> float | None:
    """Convert a ``12 Mb/s`` style string or a raw bit/s number into Mbit/s."""
    if value is None:
        return None
    if isinstance(value, int):
        return round(value / 1_000_000) if value > 100_000 else float(value)
    text = str(value).strip().lower()
    if not text or text in {"not provided", "unknown"}:
        return None
    number = ""
    for char in text:
        if char.isdigit() or char == ".":
            number += char
        elif number:
            break
    if not number:
        return None
    amount = float(number)
    if amount <= 1000 and "gb" in text:
        amount *= 1000
    if amount >= 1000:
        return round(amount)
    return amount if amount != int(amount) else int(amount)


class SystemProfiler:
    """Reads USB and Thunderbolt facts from ``system_profiler``."""

    def __init__(self, runner: Runner | None = None) -> None:
        self._run = runner or run_command

    def _json(self, data_type: str) -> tuple[list[dict[str, Any]], str | None]:
        result = self._run([SYSTEM_PROFILER, data_type, "-json"])
        if not result.ok:
            return [], result.error or f"system_profiler {data_type} failed"
        try:
            payload = json.loads(result.stdout.decode("utf-8", "replace"))
        except ValueError, plistlib.InvalidFileException:  # pragma: no cover - defensive
            return [], f"system_profiler {data_type} returned unparsable output"
        entries = payload.get(data_type) or []
        if isinstance(entries, dict):
            entries = [entries]
        return entries, None

    def usb_buses(self) -> tuple[tuple[Bus, ...], tuple[str, ...]]:
        """Return the USB bus tree plus any non-fatal warnings."""
        warnings: list[str] = []
        host_entries, host_error = self._json("SPUSBHostDataType")
        legacy_entries, legacy_error = self._json("SPUSBDataType")
        entries = host_entries or legacy_entries
        if not entries:
            if host_error or legacy_error:
                warnings.append(host_error or legacy_error or "no USB data reported")
            return (), tuple(warnings)
        legacy = not host_entries
        buses = tuple(self._parse_bus(entry, legacy=legacy) for entry in entries)
        return buses, tuple(warnings)

    def _parse_bus(self, entry: dict[str, Any], *, legacy: bool) -> Bus:
        keys = _LEGACY_KEYS if legacy else _HOST_KEYS
        name = str(entry.get("_name", "USB bus"))
        devices: list[UsbDevice] = []
        # devices may sit behind hubs, so walk the whole _items subtree
        for child in entry.get("_items") or []:
            for node in _iter_nodes(child):
                if _looks_like_device(node, keys=keys):
                    devices.append(self._parse_device(node, keys=keys, bus=name))
        return Bus(
            name=name,
            driver=_str_or_none(entry.get("Driver") or entry.get("driver")),
            location_id=_to_int(_first(entry, "USBKeyLocationID", "location_id")),
            connection=_str_or_none(_first(entry, "USBKeyHardwareType", "host_info")),
            protocol=_str_or_none(_first(entry, "USBDeviceKeyProtocolRevision", "protocol")),
            devices=tuple(devices),
        )

    def _parse_device(self, node: dict[str, Any], *, keys: dict[str, str], bus: str) -> UsbDevice:
        vendor = _str_or_none(_first(node, keys["vendor"], "USB Vendor Name"))
        if vendor and vendor.lower() in {"not provided", "unknown"}:
            vendor = None
        serial = _str_or_none(_first(node, keys["serial"], "serial_num"))
        if serial and serial.lower() in {"not provided", "unknown"}:
            serial = None
        speed = _first(node, keys["speed"], "device_speed")
        return UsbDevice(
            name=str(_first(node, "USB Product Name", "_name") or "unknown device"),
            vendor=vendor,
            vendor_id=_to_int(_first(node, keys["vendor_id"], "idVendor")),
            product_id=_to_int(_first(node, keys["product_id"], "idProduct")),
            serial=serial,
            location_id=_to_int(_first(node, keys["location"], "locationID")),
            speed_text=_str_or_none(speed),
            speed_mbps=_speed_mbps(speed),
            connection=_str_or_none(_first(node, keys["connection"], "USBKeyHardwareType"))
            or "bus",
            version=_str_or_none(_first(node, keys["version"], "bcd_device")),
            bus=bus,
            source="system_profiler",
            extra={k: v for k, v in node.items() if k not in {"_name", "_items"}},
        )

    def hardware(self) -> tuple[dict[str, str | None], tuple[str, ...]]:
        """Return model/chip facts for the header (best effort)."""
        entries, error = self._json("SPHardwareDataType")
        if not entries:
            return {}, (error,) if error else ()
        entry = entries[0]
        return (
            {
                "model": _str_or_none(entry.get("machine_name") or entry.get("model_name")),
                "chip": _str_or_none(entry.get("chip_type")),
            },
            (),
        )

    def thunderbolt(self) -> tuple[tuple[ThunderboltPort, ...], tuple[str, ...]]:
        """Return Thunderbolt/USB4 receptacles plus any non-fatal warnings."""
        entries, error = self._json("SPThunderboltDataType")
        if not entries and error:
            return (), (error,)
        ports: list[ThunderboltPort] = []
        for entry in entries:
            for index in range(1, 7):
                tag = entry.get(f"receptacle_{index}_tag")
                if not isinstance(tag, dict):
                    continue
                ports.append(
                    ThunderboltPort(
                        bus=str(_first(entry, "_name") or "thunderbolt"),
                        status=_str_or_none(tag.get("receptacle_status_key")),
                        speed=_str_or_none(tag.get("current_speed_key")),
                        receptacle=_to_int(tag.get("receptacle_id_key")),
                        device=_str_or_none(entry.get("device_name_key")),
                        vendor=_str_or_none(entry.get("vendor_name_key")),
                    )
                )
        return tuple(ports), ()


def _str_or_none(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
