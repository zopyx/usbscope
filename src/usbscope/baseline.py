"""Baseline: save a snapshot and tell whether the live machine still matches.

``usbscope baseline save <file>`` writes the current ``schema_version: 1``
snapshot document — the very same JSON ``usbscope --json`` prints, so a baseline
is interchangeable with any other snapshot a script keeps. ``usbscope baseline
check <file>`` compares that file against a fresh read and reports which
receptacles appeared, disappeared or changed state, plus the devices that came
and went.

The comparison is deliberately done on the *JSON documents*, not on two live
objects: a baseline may have been written by the Swift twin (or by an older
version), and the snapshot schema is the only contract between the two
implementations. ``seen_at`` is the one field that always differs and is
therefore ignored; a run is "identical" when no port and no device differs.

Identity rules (mirrored in the Swift twin so both agree):

* a port is keyed by its ``name`` (``USB-C@3``);
* a device is keyed by ``location_id`` when it has one, otherwise by ``name``.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .models import Snapshot
from .serialize import snapshot_to_dict, snapshot_to_json

__all__ = [
    "BaselineDiff",
    "BaselineError",
    "compare",
    "load_baseline",
    "render_diff",
    "save_baseline",
]


class BaselineError(ValueError):
    """An unreadable or non-snapshot baseline file (exit code 2)."""


def save_baseline(snapshot: Snapshot, path: str | Path) -> None:
    """Write the current snapshot as a baseline JSON document."""
    Path(path).write_text(snapshot_to_json(snapshot) + "\n", encoding="utf-8")


def load_baseline(path: str | Path) -> dict[str, Any]:
    """Read and validate a baseline document (raises :class:`BaselineError`).

    A file that cannot be read, is not JSON or is not a snapshot document is
    rejected here; the caller reports it and exits ``2`` instead of comparing
    against a half-understood file.
    """
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise BaselineError(f"cannot read baseline {path}: {exc}") from exc
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise BaselineError(f"{path} is not valid JSON: {exc}") from exc
    if not isinstance(payload, dict) or "ports" not in payload or "schema_version" not in payload:
        raise BaselineError(f"{path} is not a usbscope snapshot document")
    return payload


def _port_signature(port: Mapping[str, Any]) -> tuple[Any, ...]:
    """The part of a port that counts as "changed" (mirrored in the Swift twin)."""
    cable = port.get("cable")
    cable_kind = cable.get("kind") if isinstance(cable, Mapping) else None
    devices = port.get("devices")
    return (
        port.get("connected"),
        port.get("mode"),
        cable_kind,
        port.get("liquid_detected"),
        len(devices) if isinstance(devices, list) else 0,
    )


def _device_key(device: Mapping[str, Any]) -> str:
    """Stable identity of a device inside a snapshot document."""
    location = device.get("location_id")
    if isinstance(location, int):
        return f"loc:{location}"
    return f"name:{device.get('name')}"


def _ports(document: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    result: dict[str, Mapping[str, Any]] = {}
    for port in document.get("ports", []):
        if isinstance(port, Mapping) and isinstance(port.get("name"), str):
            result[port["name"]] = port
    return result


def _devices(document: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    """Every device of the document: on a bus and on a port, by identity."""
    result: dict[str, Mapping[str, Any]] = {}
    for bus in document.get("buses", []):
        if not isinstance(bus, Mapping):
            continue
        for device in bus.get("devices", []):
            if isinstance(device, Mapping) and isinstance(device.get("name"), str):
                result.setdefault(_device_key(device), device)
    for port in document.get("ports", []):
        if not isinstance(port, Mapping):
            continue
        for device in port.get("devices", []):
            if isinstance(device, Mapping) and isinstance(device.get("name"), str):
                result.setdefault(_device_key(device), device)
    return result


@dataclass(frozen=True, slots=True)
class BaselineDiff:
    """What differs between a saved baseline and the live snapshot."""

    appeared_ports: tuple[str, ...] = ()
    disappeared_ports: tuple[str, ...] = ()
    changed_ports: tuple[str, ...] = ()
    appeared_devices: tuple[str, ...] = ()
    disappeared_devices: tuple[str, ...] = ()

    @property
    def identical(self) -> bool:
        """True when nothing differs (ignoring ``seen_at``)."""
        return not (
            self.appeared_ports
            or self.disappeared_ports
            or self.changed_ports
            or self.appeared_devices
            or self.disappeared_devices
        )

    def to_dict(self) -> dict[str, Any]:
        """Machine readable form (``kind: baseline``)."""
        return {
            "kind": "baseline",
            "identical": self.identical,
            "appeared_ports": list(self.appeared_ports),
            "disappeared_ports": list(self.disappeared_ports),
            "changed_ports": list(self.changed_ports),
            "appeared_devices": list(self.appeared_devices),
            "disappeared_devices": list(self.disappeared_devices),
        }


def compare(previous: Mapping[str, Any], current: Mapping[str, Any]) -> BaselineDiff:
    """Diff two snapshot documents, ignoring only ``seen_at``.

    ``previous`` is the saved baseline, ``current`` the fresh live read; the
    lists are sorted so two runs cannot report the same set in a different order.
    """
    before, after = _ports(previous), _ports(current)
    appeared = tuple(sorted(name for name in after if name not in before))
    disappeared = tuple(sorted(name for name in before if name not in after))
    changed = tuple(
        sorted(
            name
            for name in after
            if name in before and _port_signature(before[name]) != _port_signature(after[name])
        )
    )
    before_devices, after_devices = _devices(previous), _devices(current)
    devices_appeared = tuple(sorted(key for key in after_devices if key not in before_devices))
    devices_disappeared = tuple(sorted(key for key in before_devices if key not in after_devices))
    return BaselineDiff(appeared, disappeared, changed, devices_appeared, devices_disappeared)


def render_diff(diff: BaselineDiff, path: str | Path) -> str:
    """Plain-text report of a baseline comparison (no Rich markup)."""
    lines = [f"baseline: {path}"]
    for label, names in (
        ("appeared ports", diff.appeared_ports),
        ("disappeared ports", diff.disappeared_ports),
        ("changed ports", diff.changed_ports),
        ("appeared devices", diff.appeared_devices),
        ("disappeared devices", diff.disappeared_devices),
    ):
        if names:
            lines.append(f"  {label}: " + ", ".join(names))
    if diff.identical:
        lines.append("identical to baseline")
    else:
        lines.append("differs from baseline")
    return "\n".join(lines)


def live_document(snapshot: Snapshot) -> dict[str, Any]:
    """The live snapshot as the same mapping a baseline file decodes to."""
    return snapshot_to_dict(snapshot)
