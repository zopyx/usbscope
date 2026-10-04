"""Attach/detach event stream (``usbscope watch --events``).

One JSON object per line per USB edge, flushed immediately so a shell script can
``usbscope watch --events | while read line`` — the shape a CI/QA rig or a shell
pipeline wants instead of a repainted table.

**Why polling and not IOKit.** The Swift app arms real ``kIOMatchedNotification``
/ ``kIOTerminatedNotification`` notifications on ``IOUSBHostDevice`` (see
``UsbScopeCore.UsbHotplugWatcher``). Python has no IOKit bridge in this project
and reaching ``IOServiceAddMatchingNotification`` would drag in PyObjC, which the
CLI deliberately does not depend on. The Python side therefore polls: it collects
one snapshot every ``interval`` seconds and diffs it against the previous one.
That is the same *triggered snapshot diff* the Swift watcher uses to resolve an
edge's identity — only the trigger differs, so the emitted events are identical.

Identity and ordering are shared with the Swift twin: a device is keyed by its
``location_id`` when it has one (otherwise its name), detaches are emitted before
attaches and each group is sorted by key, so a replayed diff is deterministic.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from datetime import datetime
from time import sleep
from typing import Any

from .models import Snapshot, UsbDevice

__all__ = [
    "Event",
    "device_identity",
    "event_dict",
    "event_line",
    "events_between",
    "iter_events",
    "poll",
]

ATTACHED = "attached"
DETACHED = "detached"


@dataclass(frozen=True, slots=True)
class Event:
    """One USB edge with the device facts macOS reported at that moment."""

    timestamp: datetime
    kind: str
    name: str
    vendor_id: int | None
    product_id: int | None
    serial: str | None
    location_id: int | None
    port: str | None


def device_identity(device: UsbDevice) -> str:
    """Stable identity of a device across two reads (location ID, else name)."""
    if device.location_id is not None:
        return f"loc:{device.location_id}"
    return f"name:{device.name}"


def _event(kind: str, device: UsbDevice, at: datetime) -> Event:
    return Event(
        timestamp=at,
        kind=kind,
        name=device.name,
        vendor_id=device.vendor_id,
        product_id=device.product_id,
        serial=device.serial,
        location_id=device.location_id,
        port=device.port,
    )


def events_between(previous: Snapshot, current: Snapshot) -> list[Event]:
    """The attach/detach events between two snapshots.

    Detaches first, then attaches, each sorted by identity — a dictionary-backed
    diff has no stable order otherwise, and the log must be reproducible. The
    timestamp is the fresh snapshot's ``seen_at`` (the moment the edge was seen).
    """
    before = {device_identity(device): device for device in previous.devices}
    after = {device_identity(device): device for device in current.devices}
    detached = [
        _event(DETACHED, before[key], current.seen_at) for key in sorted(before) if key not in after
    ]
    attached = [
        _event(ATTACHED, after[key], current.seen_at) for key in sorted(after) if key not in before
    ]
    return detached + attached


def event_dict(event: Event) -> dict[str, Any]:
    """Plain JSON-compatible form; keys sorted later, so order here is irrelevant."""
    return {
        "timestamp": event.timestamp.isoformat(timespec="seconds"),
        "kind": event.kind,
        "name": event.name,
        "vendor_id": event.vendor_id,
        "product_id": event.product_id,
        "serial": event.serial,
        "location_id": event.location_id,
        "port": event.port,
    }


def event_line(event: Event) -> str:
    """One compact, sorted JSON line (no spaces) — byte-identical to the Swift twin."""
    return json.dumps(event_dict(event), ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def poll(interval: float, collect: Callable[[], Snapshot]) -> Iterator[Snapshot]:
    """Yield snapshots forever: collect now, sleep, collect again (baseline first)."""
    while True:
        yield collect()
        sleep(interval)


def iter_events(snapshots: Iterable[Snapshot]) -> Iterator[Event]:
    """Diff a stream of snapshots into events; the first read is the baseline.

    The first snapshot never produces an event — plugging the tool in is not a
    device attach. Separated from the sleeping poll so the differ is testable.
    """
    iterator = iter(snapshots)
    try:
        previous = next(iterator)
    except StopIteration:
        return
    for current in iterator:
        yield from events_between(previous, current)
        previous = current
