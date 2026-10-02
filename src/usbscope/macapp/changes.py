"""Diffing two snapshots: what appeared, what disappeared, what changed.

The app uses this to highlight rows and to post a notification when a device is
plugged in or unplugged. Pure Python, so the whole thing is testable without a
window server.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..models import Port, Snapshot, UsbDevice

__all__ = [
    "ADDED",
    "CHANGED",
    "REMOVED",
    "ChangeSet",
    "change_tag",
    "device_key",
    "diff_snapshots",
    "port_key",
]

ADDED = "added"
REMOVED = "removed"
CHANGED = "changed"


def device_key(device: UsbDevice) -> str:
    """Return a stable identity for a device across reads.

    A serial number identifies a device best; without one the vendor/product ID
    plus the location ID is used, and the name is appended as a last resort so
    two identical models on different ports are not merged.
    """
    if device.serial:
        return f"device:serial:{device.serial}"
    vendor = f"{device.vendor_id:04x}" if device.vendor_id is not None else "????"
    product = f"{device.product_id:04x}" if device.product_id is not None else "????"
    location = f"{device.location_id:08x}" if device.location_id is not None else "????????"
    return f"device:{vendor}:{product}:{location}:{device.name.lower()}"


def port_key(port: Port) -> str:
    """Return the key a port row is addressed by."""
    return f"port:{port.name}"


def _port_signature(port: Port) -> tuple[object, ...]:
    """The part of a port's state that counts as a change."""
    mode = port.usb_transport.mode.label if port.usb_transport is not None else None
    return (port.connected, mode, port.cable.kind, port.liquid_detected, len(port.devices))


@dataclass(frozen=True, slots=True)
class ChangeSet:
    """What changed between two reads."""

    added: tuple[UsbDevice, ...] = ()
    removed: tuple[UsbDevice, ...] = ()
    changed_ports: tuple[str, ...] = ()

    @property
    def count(self) -> int:
        """Number of changes of any kind."""
        return len(self.added) + len(self.removed) + len(self.changed_ports)

    @property
    def is_empty(self) -> bool:
        """True when nothing changed."""
        return self.count == 0

    @property
    def device_count(self) -> int:
        """Number of devices that appeared or disappeared."""
        return len(self.added) + len(self.removed)

    def summary(self) -> str:
        """Short human readable description, e.g. ``1 added · 1 removed``."""
        if self.is_empty:
            return "no changes"
        parts: list[str] = []
        if self.added:
            parts.append(f"{len(self.added)} added")
        if self.removed:
            parts.append(f"{len(self.removed)} removed")
        if self.changed_ports:
            parts.append(f"{len(self.changed_ports)} port state changed")
        return " · ".join(parts)

    def tag(self, key: str) -> str | None:
        """Classify a row key as :data:`ADDED`, :data:`REMOVED` or :data:`CHANGED`."""
        if any(device_key(device) == key for device in self.added):
            return ADDED
        if any(device_key(device) == key for device in self.removed):
            return REMOVED
        if key in self.changed_ports:
            return CHANGED
        return None


def change_tag(changes: ChangeSet | None, key: str) -> str | None:
    """Convenience wrapper that tolerates ``None``."""
    return None if changes is None else changes.tag(key)


def diff_snapshots(previous: Snapshot | None, current: Snapshot) -> ChangeSet:
    """Compare two snapshots.

    Without a ``previous`` snapshot nothing is reported as added — the first read
    of a session is not a plug event.
    """
    if previous is None:
        return ChangeSet()

    before = {device_key(device): device for device in previous.devices}
    after = {device_key(device): device for device in current.devices}
    added = tuple(after[key] for key in after.keys() - before.keys())
    removed = tuple(before[key] for key in before.keys() - after.keys())

    previous_ports = {port_key(port): _port_signature(port) for port in previous.ports}
    changed_ports = tuple(
        key
        for port in current.ports
        if (key := port_key(port)) in previous_ports
        and previous_ports[key] != _port_signature(port)
    )
    return ChangeSet(added=added, removed=removed, changed_ports=changed_ports)
