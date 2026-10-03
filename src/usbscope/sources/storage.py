"""USB mass-storage inventory from ``diskutil``.

``diskutil list -plist`` names the whole disks; ``diskutil info -plist
<device>`` carries the one fact that says a disk hangs off USB — its
``BusProtocol``. Only whole disks whose bus protocol is ``USB`` are kept, so an
internal SSD or an APFS container never shows up here.

Absence is normal, not an error: a Mac with no USB storage reports no matching
disk and the inventory is empty. A missing or failing ``diskutil`` degrades to
the same empty inventory instead of aborting the run (and without a warning —
there is genuinely nothing to say about a machine that has no USB storage).

What this cannot see, and does not pretend to: the filesystem contents, whether
a volume is encrypted, or a device macOS does not present as a whole disk.
"""

from __future__ import annotations

import plistlib
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from .shell import CommandResult, run_command, system_binary

__all__ = ["StorageDevice", "StorageSource", "format_bytes", "parse_storage"]

Runner = Callable[[list[str]], CommandResult]

DISKUTIL = system_binary("diskutil", "/usr/sbin/diskutil", "/usr/bin/diskutil")


@dataclass(frozen=True, slots=True)
class StorageDevice:
    """A whole disk macOS reports over the USB bus."""

    identifier: str
    name: str | None = None
    bus_protocol: str | None = None
    capacity_bytes: int | None = None
    read_only: bool | None = None
    removable: bool | None = None
    mount_point: str | None = None
    content: str | None = None

    @property
    def label(self) -> str:
        """Volume/media name when known, otherwise the BSD device."""
        return self.name or self.identifier

    @property
    def capacity_text(self) -> str | None:
        """Human capacity such as ``32.0 GB`` (``None`` when unknown)."""
        return format_bytes(self.capacity_bytes)


def format_bytes(value: int | None) -> str | None:
    """Format a byte count as ``GB``/``MB``/``kB``/``B`` (SI, not GiB)."""
    if value is None:
        return None
    if value >= 1_000_000_000:
        return f"{value / 1_000_000_000:.1f} GB"
    if value >= 1_000_000:
        return f"{value / 1_000_000:.0f} MB"
    if value >= 1_000:
        return f"{value / 1_000:.0f} kB"
    return f"{value} B"


def _text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    if not text or text.lower() in {"none", "null", "<null>"}:
        return None
    return text


def _int(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    try:
        return int(str(value).strip(), 0)
    except ValueError:
        return None


def _bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"yes", "true"}:
            return True
        if lowered in {"no", "false"}:
            return False
    return None


def _whole_disks(listing: dict[str, Any]) -> list[str]:
    """The whole-disk identifiers of ``diskutil list -plist``, in its order.

    ``WholeDisks`` is the direct list; older/odd payloads are covered by the
    fallback over ``AllDisksAndPartitions``.
    """
    identifiers = listing.get("WholeDisks")
    if isinstance(identifiers, list):
        return [item for item in identifiers if isinstance(item, str)]
    return [
        entry["DeviceIdentifier"]
        for entry in listing.get("AllDisksAndPartitions", [])
        if isinstance(entry, dict) and isinstance(entry.get("DeviceIdentifier"), str)
    ]


def _read_only(info: dict[str, Any]) -> bool | None:
    """Read-only state from ``Writable``, falling back to ``MediaReadOnly``."""
    writable = _bool(info.get("Writable"))
    if writable is not None:
        return not writable
    return _bool(info.get("MediaReadOnly"))


def _capacity(info: dict[str, Any]) -> int | None:
    total = _int(info.get("TotalSize"))
    return total if total is not None else _int(info.get("Size"))


def parse_storage(
    listing: dict[str, Any], infos: dict[str, dict[str, Any]]
) -> tuple[StorageDevice, ...]:
    """Build the USB storage devices from a disk list and per-disk info dicts.

    Pure: :class:`StorageSource` gathers the two plists and hands them here, so
    the mapping (whole disks only, ``BusProtocol == USB``) is testable without
    running ``diskutil``.
    """
    devices: list[StorageDevice] = []
    for identifier in _whole_disks(listing):
        info = infos.get(identifier)
        if not isinstance(info, dict):
            continue
        protocol = _text(info.get("BusProtocol"))
        if protocol is None or protocol.upper() != "USB":
            continue
        removable = _bool(info.get("Removable"))
        if removable is None:
            removable = _bool(info.get("RemovableMedia"))
        devices.append(
            StorageDevice(
                identifier=identifier,
                name=_text(info.get("VolumeName")) or _text(info.get("MediaName")),
                bus_protocol=protocol,
                capacity_bytes=_capacity(info),
                read_only=_read_only(info),
                removable=removable,
                mount_point=_text(info.get("MountPoint")),
                content=_text(info.get("Content")),
            )
        )
    return tuple(devices)


class StorageSource:
    """Reads the USB mass-storage inventory through ``diskutil``."""

    def __init__(self, runner: Runner | None = None) -> None:
        self._run = runner or run_command

    def _plist(self, argv: list[str]) -> dict[str, Any] | None:
        result = self._run(argv)
        if not result.ok:
            return None
        try:
            value = plistlib.loads(result.stdout)
        except Exception:
            return None
        return value if isinstance(value, dict) else None

    def inventory(self) -> tuple[tuple[StorageDevice, ...], tuple[str, ...]]:
        """USB mass-storage devices plus the (always empty) warnings tuple.

        A failing ``diskutil`` and a machine without USB storage both yield an
        empty inventory; neither is an error, so no warning is reported. The
        warnings slot keeps the signature of the other adapters.
        """
        listing = self._plist([DISKUTIL, "list", "-plist"])
        if listing is None:
            return (), ()
        infos: dict[str, dict[str, Any]] = {}
        for identifier in _whole_disks(listing):
            info = self._plist([DISKUTIL, "info", "-plist", identifier])
            if info is not None:
                infos[identifier] = info
        return parse_storage(listing, infos), ()
