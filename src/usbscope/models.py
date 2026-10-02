"""Domain model of the USB subsystem as reported by macOS.

The model is deliberately free of any I/O: every adapter (``system_profiler``,
``ioreg``) translates raw facts into these objects and the presentation layer
renders them.  All values are derived from what the OS actually reports - when
a fact is unknown it stays ``None`` instead of being guessed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from typing import Any

__all__ = [
    "Bus",
    "Cable",
    "Port",
    "Snapshot",
    "ThunderboltPort",
    "Transport",
    "UsbDevice",
    "UsbMode",
]

_MBPS_TO_MODE: dict[float, str] = {
    1.5: "low_speed",
    12.0: "full_speed",
    480.0: "high_speed",
    5000.0: "super_speed",
    10000.0: "super_speed_plus",
    20000.0: "usb4_20",
    40000.0: "usb4_40",
    80000.0: "usb4_80",
}

_MODE_LABELS: dict[str, str] = {
    "unknown": "unknown",
    "low_speed": "USB 1.0 Low-Speed · 1.5 Mbit/s",
    "full_speed": "USB 1.1 Full-Speed · 12 Mbit/s",
    "high_speed": "USB 2.0 High-Speed · 480 Mbit/s",
    "super_speed": "USB 3.2 Gen 1 · 5 Gbit/s",
    "super_speed_plus": "USB 3.2 Gen 2 · 10 Gbit/s",
    "usb4_20": "USB 3.2 Gen 2x2 / USB4 · 20 Gbit/s",
    "usb4_40": "USB4 · 40 Gbit/s",
    "usb4_80": "USB4 v2 · 80 Gbit/s",
}

_MODE_SHORT: dict[str, str] = {
    "unknown": "?",
    "low_speed": "1.0 LS",
    "full_speed": "1.1 FS",
    "high_speed": "2.0 HS",
    "super_speed": "3.2 G1",
    "super_speed_plus": "3.2 G2",
    "usb4_20": "3.2 G2x2",
    "usb4_40": "USB4 40",
    "usb4_80": "USB4 80",
}

_RATE_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(G|M)?(?:bit|b)", re.IGNORECASE)

_KEYWORD_TO_MODE: tuple[tuple[str, str], ...] = (
    ("low speed", "low_speed"),
    ("full speed", "full_speed"),
    ("high speed", "high_speed"),
    ("superspeedplus", "super_speed_plus"),
    ("super speed plus", "super_speed_plus"),
    ("superspeed", "super_speed"),
    ("super speed", "super_speed"),
    ("usb4", "usb4_40"),
)


class UsbMode(StrEnum):
    """Negotiated USB link mode (speed class)."""

    UNKNOWN = "unknown"
    LOW_SPEED = "low_speed"
    FULL_SPEED = "full_speed"
    HIGH_SPEED = "high_speed"
    SUPER_SPEED = "super_speed"
    SUPER_SPEED_PLUS = "super_speed_plus"
    USB4_20 = "usb4_20"
    USB4_40 = "usb4_40"
    USB4_80 = "usb4_80"

    @property
    def label(self) -> str:
        """Human readable name including the nominal rate."""
        return _MODE_LABELS[self.value]

    @property
    def short(self) -> str:
        """Compact name for narrow table columns."""
        return _MODE_SHORT[self.value]

    @property
    def rank(self) -> int:
        """Sort/compare helper: higher is faster, 0 for unknown."""
        return _MODE_RANK[self.value]

    @classmethod
    def from_mbps(cls, mbps: int | float | None) -> UsbMode:
        """Classify a link rate given in Mbit/s (values above 100000 are read as bit/s)."""
        if mbps is None:
            return cls.UNKNOWN
        value = float(mbps)
        if value > 100_000:  # reported in bit/s
            value /= 1_000_000
        # tolerate minor rounding differences in OS output
        for known, name in _MBPS_TO_MODE.items():
            if abs(value - known) <= known * 0.05:
                return cls(name)
        return cls.UNKNOWN

    @classmethod
    def from_text(cls, text: str | None) -> UsbMode:
        """Classify descriptive OS strings such as ``12 Mbps (Full Speed)``."""
        if not text:
            return cls.UNKNOWN
        stripped = text.strip()
        if stripped.lower() in {"none", "no link", "n/a", "-"}:
            return cls.UNKNOWN
        lowered = stripped.lower()
        for keyword, name in _KEYWORD_TO_MODE:
            if keyword in lowered:
                return cls(name)
        match = _RATE_RE.search(stripped)
        if match is None:
            return cls.UNKNOWN
        amount = float(match.group(1))
        unit = (match.group(2) or "M").upper()
        return cls.from_mbps(amount * 1000 if unit == "G" else amount)


_MODE_RANK: dict[str, int] = {
    "unknown": 0,
    "low_speed": 1,
    "full_speed": 2,
    "high_speed": 3,
    "super_speed": 4,
    "super_speed_plus": 5,
    "usb4_20": 6,
    "usb4_40": 7,
    "usb4_80": 8,
}


@dataclass(frozen=True, slots=True)
class UsbDevice:
    """A single USB device as seen on a bus or a port."""

    name: str
    vendor: str | None = None
    vendor_id: int | None = None
    product_id: int | None = None
    serial: str | None = None
    location_id: int | None = None
    speed_text: str | None = None
    speed_mbps: float | None = None
    connection: str | None = None
    version: str | None = None
    bus: str | None = None
    port: str | None = None
    port_type: str | None = None
    transport: str | None = None
    generation: str | None = None
    restricted: bool | None = None
    source: str = "system_profiler"
    extra: dict[str, Any] = field(default_factory=dict, compare=False)

    @property
    def mode(self) -> UsbMode:
        """Negotiated link mode of this device."""
        if self.speed_mbps is not None:
            return UsbMode.from_mbps(self.speed_mbps)
        return UsbMode.from_text(self.speed_text)

    @property
    def id_string(self) -> str:
        """``vendor:product`` in the usual ``0x1050:0x0407`` notation."""
        vendor = f"0x{self.vendor_id:04x}" if self.vendor_id is not None else "?"
        product = f"0x{self.product_id:04x}" if self.product_id is not None else "?"
        return f"{vendor}:{product}"

    @property
    def label(self) -> str:
        """Name plus vendor, whichever are known."""
        if self.vendor and not self.name.lower().startswith(self.vendor.lower()):
            return f"{self.vendor} {self.name}"
        return self.name


@dataclass(frozen=True, slots=True)
class Cable:
    """What the port controller knows about the attached cable.

    ``emarker`` is only true when the controller actually received an e-marker
    response (the ``SOP'``/``SOP''`` ordered set, i.e. a cable plug).  The
    ``SOP`` node is the PD port partner (the device/charger on the other end),
    so it is kept separately and never presented as cable proof.
    """

    attached: bool = False
    emarker: bool = False
    active: bool = False
    optical: bool = False
    authentication: str | None = None
    hash_status: str | None = None
    pd_spec_revision: int | None = None

    @property
    def kind(self) -> str:
        """Coarse cable class derived from the controller flags."""
        if not self.attached:
            return "–"
        if self.optical:
            return "optical"
        if self.active:
            return "active"
        if self.emarker:
            return "e-marked"
        return "unknown"


@dataclass(frozen=True, slots=True)
class Transport:
    """A logical transport of a port: CC, USB2, USB3, DisplayPort, SD …"""

    kind: str
    active: bool
    rate_text: str | None = None
    speed_mbps: float | None = None
    generation: str | None = None
    signaling: str | None = None
    data_role: str | None = None
    lanes: int | None = None
    restricted: bool | None = None
    trm_state: str | None = None
    trm_profile: str | None = None
    hash_status: str | None = None

    @property
    def mode(self) -> UsbMode:
        """Link mode of this transport."""
        if self.speed_mbps is not None:
            return UsbMode.from_mbps(self.speed_mbps)
        return UsbMode.from_text(self.rate_text)


@dataclass(frozen=True, slots=True)
class Port:
    """A physical receptacle as exposed by the hardware port manager."""

    description: str
    kind: str
    connected: bool = False
    number: int | None = None
    connect_type: str | None = None
    super_speed_active: bool | None = None
    plug_orientation: int | None = None
    displayport_pin_assignment: int | None = None
    liquid_detected: bool | None = None
    authorization: str | None = None
    firmware: str | None = None
    power_in: tuple[str, ...] = ()
    cable: Cable = field(default_factory=Cable)
    transports: tuple[Transport, ...] = ()
    devices: tuple[UsbDevice, ...] = ()

    @property
    def name(self) -> str:
        """``USB-C@3`` style short name."""
        head, _, tail = self.description.partition("@")
        prefix = head.removeprefix("Port-")
        return f"{prefix}@{tail}" if tail else prefix

    def transport(self, kind: str) -> Transport | None:
        """First transport of the given kind, if any."""
        for item in self.transports:
            if item.kind.lower() == kind.lower():
                return item
        return None

    @property
    def active_transports(self) -> tuple[Transport, ...]:
        """Transports currently carrying traffic."""
        return tuple(item for item in self.transports if item.active)

    @property
    def usb_transport(self) -> Transport | None:
        """The USB data transport of this port, preferring the faster one."""
        candidates = [
            item for item in self.transports if item.kind.lower() in {"usb2", "usb3", "usb4"}
        ]
        if not candidates:
            return None
        return max(candidates, key=lambda item: (item.active, item.mode.rank))

    @property
    def mode(self) -> UsbMode:
        """Negotiated USB mode of this port (unknown when nothing is active)."""
        transport = self.usb_transport
        return transport.mode if transport else UsbMode.UNKNOWN


@dataclass(frozen=True, slots=True)
class Bus:
    """USB host controller (bus) with the devices attached to it."""

    name: str
    driver: str | None = None
    location_id: int | None = None
    connection: str | None = None
    protocol: str | None = None
    devices: tuple[UsbDevice, ...] = ()


@dataclass(frozen=True, slots=True)
class ThunderboltPort:
    """Thunderbolt/USB4 receptacle as reported by ``system_profiler``."""

    bus: str
    status: str | None = None
    speed: str | None = None
    receptacle: int | None = None
    device: str | None = None
    vendor: str | None = None

    @property
    def connected(self) -> bool:
        """Whether something is plugged into this receptacle."""
        if self.status is None:
            return False
        return "no_devices" not in self.status and "no devices" not in self.status


@dataclass(frozen=True, slots=True)
class Snapshot:
    """Everything the tool knows about the USB subsystem at one point in time."""

    host: str
    os_version: str
    seen_at: datetime
    model: str | None = None
    chip: str | None = None
    ports: tuple[Port, ...] = ()
    buses: tuple[Bus, ...] = ()
    thunderbolt: tuple[ThunderboltPort, ...] = ()
    warnings: tuple[str, ...] = ()

    @property
    def devices(self) -> tuple[UsbDevice, ...]:
        """All known devices, deduplicated by location ID (or by name as fallback)."""
        seen: set[tuple[str, int | str]] = set()
        collected: list[UsbDevice] = []
        for device in (*self._bus_devices, *(d for port in self.ports for d in port.devices)):
            key: tuple[str, int | str] = (
                ("loc", device.location_id) if device.location_id else ("name", device.name)
            )
            if key in seen:
                continue
            seen.add(key)
            collected.append(device)
        return tuple(collected)

    @property
    def _bus_devices(self) -> tuple[UsbDevice, ...]:
        return tuple(device for bus in self.buses for device in bus.devices)

    @property
    def connected_ports(self) -> tuple[Port, ...]:
        """Ports with an active connection."""
        return tuple(port for port in self.ports if port.connected)

    @property
    def emarked_cables(self) -> tuple[Port, ...]:
        """Ports reporting an electronically marked cable."""
        return tuple(port for port in self.ports if port.cable.emarker)
