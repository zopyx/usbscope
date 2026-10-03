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
    "Charging",
    "Port",
    "PowerOption",
    "PowerSource",
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
    # USB descriptor basics reported by the device itself (`ioreg -p IOUSB`):
    # the device-level class triple, the supported USB version, the control
    # endpoint packet size, the number of configurations, the enumeration speed
    # code and — from the tree shape — the hub tier, the parent hub and the
    # device address.
    device_class: int | None = None
    device_subclass: int | None = None
    device_protocol: int | None = None
    class_name: str | None = None
    bcd_usb: str | None = None
    max_packet_size0: int | None = None
    num_configurations: int | None = None
    speed_code: int | None = None
    tier: int | None = None
    parent: str | None = None
    address: int | None = None
    extra: dict[str, Any] = field(default_factory=dict, compare=False)

    @property
    def mode(self) -> UsbMode:
        """Negotiated link mode of this device."""
        if self.speed_mbps is not None:
            return UsbMode.from_mbps(self.speed_mbps)
        return UsbMode.from_text(self.speed_text)

    @property
    def class_text(self) -> str | None:
        """Human form of the device class triple, e.g. ``HID (3/1/1)``.

        A device class of ``0`` means the class is declared per interface, which
        macOS only exposes through an ``IOUSBHostDevice`` user client — so it is
        reported as ``per-interface`` instead of guessed.
        """
        if self.device_class is None:
            return None
        base = self.class_name or f"0x{self.device_class:02x}"
        if self.device_class == 0:
            return base
        sub = self.device_subclass if self.device_subclass is not None else "?"
        proto = self.device_protocol if self.device_protocol is not None else "?"
        return f"{base} ({self.device_class}/{sub}/{proto})"

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


# The controller's PDO classes (``IOPortFeaturePowerSourceOption*``) in human form.
POWER_OPTION_KINDS: dict[str, str] = {
    "fixed": "fixed",
    "adjustable": "adjustable (PPS)",
    "variable": "variable",
    "battery": "battery",
}


@dataclass(frozen=True, slots=True)
class PowerOption:
    """One power source option (a PDO) as the port controller lists it.

    ``kind`` is the PDO type the controller reports in the option's ``Class``
    key (``fixed``, ``adjustable`` for a PPS/APDO, ``variable``, ``battery``);
    ``uuid`` is the controller's stable identity for the option, which is what
    tells two otherwise identical contracts apart across reads.
    """

    max_power_mw: int | None = None
    max_current_ma: int | None = None
    voltage_mv: int | None = None
    kind: str | None = None
    uuid: str | None = None

    @property
    def watts(self) -> float | None:
        """Nominal power of this option in watt."""
        return None if self.max_power_mw is None else self.max_power_mw / 1000

    @property
    def kind_label(self) -> str | None:
        """Human name of the PDO type (``fixed``, ``adjustable (PPS)`` …)."""
        return POWER_OPTION_KINDS.get(self.kind or "", self.kind)

    @property
    def label(self) -> str:
        """Compact ``20 V · 3 A · 60 W`` form, omitting what is unknown."""
        parts = [
            f"{self.voltage_mv / 1000:g} V" if self.voltage_mv is not None else None,
            f"{self.max_current_ma / 1000:g} A" if self.max_current_ma is not None else None,
            f"{self.max_power_mw / 1000:g} W" if self.max_power_mw is not None else None,
        ]
        return " · ".join(part for part in parts if part)


@dataclass(frozen=True, slots=True)
class PowerSource:
    """A power provider the port controller reports, and what it negotiated.

    ``selected`` marks the provider that won the power negotiation; macOS marks
    it with a ``[*]`` in the registry name and only that node carries a
    ``WinningPowerSourceOption``. Every source lists the options it offers (a
    charger that speaks USB-PD publishes its full PDO menu here).
    """

    name: str
    source_type: int | None = None
    priority: int | None = None
    selected: bool = False
    winning: PowerOption | None = None
    options: tuple[PowerOption, ...] = ()


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
    # Optional port-controller details. They are raw enumeration values (macOS
    # does not document them), so they stay verbatim and are only surfaced in
    # the verbose CLI output, the detail popover and the JSON snapshot.
    pin_configuration: tuple[tuple[str, int], ...] = ()
    usb_mode_type: int | None = None
    accessory_mode: int | None = None
    power_mode: int | None = None
    active_power_mode: int | None = None
    supported_power_modes: tuple[int, ...] = ()
    power_current_limits: tuple[int, ...] = ()
    liquid_state: str | None = None
    liquid_measurement: str | None = None
    liquid_pin: str | None = None
    liquid_mitigations: bool | None = None
    liquid_override: bool | None = None
    power_sources: tuple[PowerSource, ...] = ()
    cable: Cable = field(default_factory=Cable)
    transports: tuple[Transport, ...] = ()
    devices: tuple[UsbDevice, ...] = ()

    @property
    def name(self) -> str:
        """``USB-C@3`` style short name."""
        head, _, tail = self.description.partition("@")
        prefix = head.removeprefix("Port-")
        return f"{prefix}@{tail}" if tail else prefix

    @property
    def pins_text(self) -> str:
        """Non-zero USB-C pin assignment, e.g. ``rx2=4, tx2=3``.

        An idle port reports all pins as ``0``; those entries are dropped so the
        string stays readable (and is empty when the port has no pin data).
        """
        return ", ".join(f"{name}={value}" for name, value in self.pin_configuration if value)

    @property
    def usb_mode_text(self) -> str | None:
        """Port-controller USB mode with the connect type it was paired with.

        When nothing is attached the controller pairs
        ``IOAccessoryUSBConnectType = 0`` with the literal string ``None``; that
        zero enumeration is dropped instead of being shown as a value.
        """
        if self.usb_mode_type is None:
            return None
        connect = self.connect_type
        if connect is None or connect.strip() in {"", "0", "None"}:
            return str(self.usb_mode_type)
        return f"{self.usb_mode_type} ({connect})"

    @property
    def power_contract(self) -> PowerOption | None:
        """The power option this port negotiated (``None`` when nothing is attached).

        Note that this is a ceiling, not a measurement: the port controller
        publishes what the two sides agreed on. What the machine really draws is
        only reported system wide — see :class:`Charging`.
        """
        for source in self.power_sources:
            if source.selected and source.winning is not None:
                return source.winning
        return None

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
class Charging:
    """Live power and charging telemetry of the battery and the adapter.

    macOS aggregates these numbers for the whole machine (adapter input, system
    load, flow into the battery) — they are *not* per USB-C port. Per port the
    port controller publishes the negotiated contract only, see
    :attr:`Port.power_contract`.
    """

    connected: bool | None = None
    charging: bool | None = None
    fully_charged: bool | None = None
    state_of_charge: int | None = None
    #: while charging this is the time to full, otherwise the runtime left
    time_remaining_minutes: int | None = None
    system_power_in_mw: int | None = None
    system_voltage_in_mv: int | None = None
    system_current_in_ma: int | None = None
    system_load_mw: int | None = None
    battery_power_mw: int | None = None
    battery_voltage_mv: int | None = None
    battery_current_ma: int | None = None
    adapter_power_mw: int | None = None
    adapter_voltage_mv: int | None = None
    adapter_current_ma: int | None = None
    adapter_efficiency_loss_mw: int | None = None
    not_charging_reason: int | None = None
    slow_charging_reason: int | None = None
    thermally_limited_seconds: int | None = None


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
    charging: Charging | None = None
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
