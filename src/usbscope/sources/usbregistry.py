"""Adapter for the USB device tree (``ioreg -p IOUSB``).

Where ``system_profiler`` names a device and ``ioreg -p IOPort`` describes the
*receptacle*, this plane carries what the device itself reports to the host
controller: the USB descriptor basics (``bDeviceClass``/``SubClass``/
``Protocol``, ``bcdUSB``, ``bMaxPacketSize0``, ``bNumConfigurations``), the
enumeration speed code, the device address and — from the tree shape — the hub
tier and the parent hub.

The full interface/endpoint descriptor tree is **not** here: it needs an
``IOUSBHostDevice`` user client (an entitlement), so usbscope reports the device
level honestly and marks a class of ``0`` as ``per-interface`` instead of
guessing.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import Any

from ..models import UsbDevice
from .shell import CommandResult, run_command, system_binary

__all__ = ["USBRegistrySource", "parse_usb_devices"]

Runner = Callable[[list[str]], CommandResult]

IOREG = system_binary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")

# USB-IF base class codes (USB 2.0 spec, table 9-6) plus the common vendor ranges.
USB_CLASS_NAMES: dict[int, str] = {
    0x00: "per-interface",
    0x01: "audio",
    0x02: "communications",
    0x03: "HID",
    0x05: "physical",
    0x06: "image",
    0x07: "printer",
    0x08: "mass storage",
    0x09: "hub",
    0x0A: "CDC data",
    0x0B: "smart card",
    0x0C: "content security",
    0x0D: "video",
    0x0E: "health",
    0x0F: "audio/video",
    0x10: "billboard",
    0x11: "USB bridge",
    0xDC: "diagnostic",
    0xE0: "wireless",
    0xEF: "miscellaneous",
    0xFE: "application specific",
    0xFF: "vendor specific",
}

# ``Device Speed`` / ``USBSpeed`` enumeration of the host controller stack.
_SPEED_CODES: dict[int, str] = {
    0: "low_speed",
    1: "full_speed",
    2: "high_speed",
    3: "super_speed",
    4: "super_speed_plus",
}

_DEVICE_MARKERS = ("bDeviceClass", "UsbDeviceSignature", "Device Speed")

# internal-only keys, not part of the domain facts
_NOISE = {"IORegistryEntryChildren", "IOObjectClass", "IOClass", "IONameMatch"}


def class_name(value: int | None) -> str | None:
    """Human name of a USB base class code (``None`` when unknown)."""
    if value is None:
        return None
    return USB_CLASS_NAMES.get(value, f"0x{value:02x}")


def speed_code_name(value: int | None) -> str | None:
    """Name of a controller speed code (``1`` → ``full_speed``)."""
    if value is None:
        return None
    return _SPEED_CODES.get(value, f"code {value}")


def format_bcd_usb(value: int | None) -> str | None:
    """``512`` (``0x0200``) → ``2.00`` — the USB specification version."""
    if value is None or value <= 0:
        return None
    return f"{value >> 8}.{(value >> 4) & 0xF}{(value & 0xF)}"


def _int(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    try:
        return int(str(value).strip(), 0)
    except ValueError:
        return None


def _children(node: dict[str, Any]) -> list[dict[str, Any]]:
    kids = node.get("IORegistryEntryChildren") or []
    return [child for child in kids if isinstance(child, dict)]


def _name(node: dict[str, Any]) -> str | None:
    value = node.get("USB Product Name") or node.get("IORegistryEntryName")
    return str(value) if value else None


def _is_device(node: dict[str, Any]) -> bool:
    return any(marker in node for marker in _DEVICE_MARKERS)


def _parse_device(node: dict[str, Any], tier: int, parent: str | None) -> UsbDevice:
    device_class = _int(node.get("bDeviceClass"))
    bits = _int(node.get("UsbLinkSpeed"))
    speed_mbps = round(bits / 1_000_000) if bits and bits > 100_000 else None
    return UsbDevice(
        name=_name(node) or "unknown device",
        vendor=str(node["USB Vendor Name"]) if node.get("USB Vendor Name") else None,
        vendor_id=_int(node.get("idVendor")),
        product_id=_int(node.get("idProduct")),
        location_id=_int(node.get("locationID")),
        speed_mbps=speed_mbps,
        speed_text=f"{speed_mbps} Mbit/s" if speed_mbps else None,
        version=f"0x{value:04x}" if (value := _int(node.get("bcdDevice"))) else None,
        connection="Removable" if node.get("UserInstallable") else None,
        device_class=device_class,
        device_subclass=_int(node.get("bDeviceSubClass")),
        device_protocol=_int(node.get("bDeviceProtocol")),
        class_name=class_name(device_class),
        bcd_usb=format_bcd_usb(_int(node.get("bcdUSB"))),
        max_packet_size0=_int(node.get("bMaxPacketSize0")),
        num_configurations=_int(node.get("bNumConfigurations")),
        speed_code=_int(node.get("Device Speed")),
        tier=tier,
        parent=parent,
        address=_int(node.get("kUSBAddress") or node.get("USB Address")),
        source="ioreg-usb",
        extra={
            key: value
            for key, value in node.items()
            if key not in _NOISE and key not in {"UsbDeviceSignature"}
        },
    )


def _iter_devices(
    node: dict[str, Any], depth: int = 0, parent: str | None = None
) -> Iterator[tuple[dict[str, Any], int, str | None]]:
    """Yield every device node with its tier and the hub it hangs off.

    A device directly on a controller is tier 1; behind a hub, tier 2, and so on
    (``UsbHostControllerTierLimit`` is 6 on Apple silicon).
    """
    for child in _children(node):
        if _is_device(child):
            yield child, depth + 1, parent
            yield from _iter_devices(child, depth + 1, _name(child))
        else:
            yield from _iter_devices(child, depth, parent)


def parse_usb_devices(root: dict[str, Any]) -> tuple[UsbDevice, ...]:
    """Translate a parsed ``-p IOUSB`` plist into devices."""
    return tuple(_parse_device(node, tier, parent) for node, tier, parent in _iter_devices(root))


class USBRegistrySource:
    """Reads the USB device tree the host controllers publish."""

    def __init__(self, runner: Runner | None = None) -> None:
        self._run = runner or run_command

    def tree(self) -> tuple[dict[str, Any] | None, str | None]:
        """The parsed ``IOUSB`` plane and an optional warning."""
        result = self._run([IOREG, "-a", "-l", "-w0", "-p", "IOUSB"])
        if not result.ok:
            return None, result.error or "ioreg failed"
        import plistlib

        try:
            tree = plistlib.loads(result.stdout)
        except Exception:
            return None, "ioreg returned unparsable output"
        if not isinstance(tree, dict):
            return None, "ioreg returned an unexpected structure"
        return tree, None

    def devices(self) -> tuple[tuple[UsbDevice, ...], tuple[str, ...]]:
        """The devices of the USB tree plus any non-fatal warnings.

        Unlike the port controller, an empty tree is not a problem: a Mac with
        nothing plugged in reports no ``IOUSBHostDevice`` at all.
        """
        tree, warning = self.tree()
        if tree is None:
            return (), (warning,) if warning else ()
        return parse_usb_devices(tree), ()
