"""Presentation model for the macOS app.

Pure Python: it turns a :class:`~usbscope.models.Snapshot` into table models and
header/status strings. The AppKit layer only maps the style names onto
``NSColor``/fonts, which keeps the UI logic testable without a window server.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from ..models import Port, Snapshot, UsbDevice, UsbMode

__all__ = [
    "VIEWS",
    "Cell",
    "Column",
    "Style",
    "TableModel",
    "header_text",
    "status_text",
    "summary_text",
    "table_model",
]

VIEWS = ("ports", "cables", "devices", "thunderbolt")


class Style(StrEnum):
    """Semantic cell style, translated to NSColor by the app layer."""

    DEFAULT = "default"
    DIM = "dim"
    BOLD = "bold"
    GREEN = "green"
    YELLOW = "yellow"
    RED = "red"
    CYAN = "cyan"
    MAGENTA = "magenta"


@dataclass(frozen=True, slots=True)
class Column:
    """One table column."""

    key: str
    title: str
    width: float
    monospaced: bool = True


@dataclass(frozen=True, slots=True)
class Cell:
    """One table cell."""

    text: str
    style: Style = Style.DEFAULT


@dataclass(frozen=True, slots=True)
class TableModel:
    """The table shown for one view."""

    columns: tuple[Column, ...]
    rows: tuple[tuple[Cell, ...], ...]
    empty_message: str = ""

    @property
    def row_count(self) -> int:
        """Number of rows."""
        return len(self.rows)


_DIM = Cell("–", Style.DIM)


def _mode_style(mode: UsbMode) -> Style:
    if mode.rank >= 7:
        return Style.MAGENTA
    if mode.rank >= 4:
        return Style.CYAN
    if mode.rank >= 3:
        return Style.GREEN
    if mode.rank >= 1:
        return Style.YELLOW
    return Style.DIM


def _state_cell(port: Port) -> Cell:
    return Cell("● connected", Style.GREEN) if port.connected else Cell("○ free", Style.DIM)


def _mode_cell(port: Port) -> Cell:
    transport = port.usb_transport
    if transport is None or not transport.active:
        if port.connected:
            return Cell("no USB data", Style.YELLOW)
        return _DIM
    return Cell(transport.mode.label, _mode_style(transport.mode))


def _transports_cell(port: Port) -> Cell:
    if not port.transports:
        return _DIM
    parts = [
        f"{item.kind} {'●' if item.active else '○'}" for item in port.transports if item.active
    ]
    idle = [item.kind for item in port.transports if not item.active]
    text = " · ".join(parts) if parts else "idle"
    if idle:
        text += f"  ({', '.join(idle)} idle)"
    return Cell(text, Style.CYAN if parts else Style.DIM)


def _cable_cell(port: Port) -> Cell:
    cable = port.cable
    if not cable.attached:
        return _DIM
    return Cell(cable.kind, Style.CYAN if cable.emarker else Style.DIM)


def _notes_cell(port: Port) -> Cell:
    notes: list[tuple[str, Style]] = []
    if port.devices:
        names = ", ".join(device.name for device in port.devices)
        notes.append((f"{len(port.devices)} device(s): {names}", Style.DEFAULT))
    displayport = port.transport("DisplayPort")
    if displayport is not None and displayport.active:
        detail = displayport.rate_text or ""
        notes.append((f"DP alt mode{' ' + detail if detail else ''}", Style.CYAN))
    if port.power_in:
        notes.append(("power in: " + ", ".join(port.power_in), Style.CYAN))
    if port.connected and port.usb_transport is None:
        notes.append(("charger/accessory only", Style.YELLOW))
    if port.liquid_detected:
        notes.append(("liquid detected", Style.RED))
    if any(item.restricted and item.active for item in port.transports):
        notes.append(("restricted by macOS", Style.YELLOW))
    if not notes:
        return _DIM
    styles = {style for _text, style in notes}
    # the most severe note decides the row colour
    severity = (
        Style.RED
        if Style.RED in styles
        else Style.YELLOW
        if Style.YELLOW in styles
        else Style.DEFAULT
    )
    return Cell(" · ".join(text for text, _style in notes), severity)


def _ports_model(snapshot: Snapshot) -> TableModel:
    columns = (
        Column("port", "Port", 110),
        Column("type", "Type", 90, monospaced=False),
        Column("state", "State", 110, monospaced=False),
        Column("mode", "Mode", 210),
        Column("transports", "Transports", 240),
        Column("cable", "Cable", 90),
        Column("notes", "Notes", 320, monospaced=False),
    )
    rows = tuple(
        (
            Cell(port.name, Style.BOLD),
            Cell(port.kind, Style.DIM if port.kind in {"HDMI", "SD Card"} else Style.DEFAULT),
            _state_cell(port),
            _mode_cell(port),
            _transports_cell(port),
            _cable_cell(port),
            _notes_cell(port),
        )
        for port in snapshot.ports
    )
    return TableModel(columns, rows, empty_message="No ports reported by the port controller.")


def _cables_model(snapshot: Snapshot) -> TableModel:
    columns = (
        Column("port", "Port", 110),
        Column("cable", "Cable", 100),
        Column("auth", "CC authentication", 150, monospaced=False),
        Column("hash", "Hash (CC / USB)", 150),
        Column("spec", "PD spec", 70),
        Column("power", "Power in", 200, monospaced=False),
        Column("liquid", "Liquid", 80, monospaced=False),
        Column("fw", "Controller fw", 120),
    )

    def hash_cell(port: Port) -> Cell:
        cable = port.cable
        if not cable.attached:
            return _DIM
        usb_hash = next(
            (
                item.hash_status
                for item in port.transports
                if item.kind.upper().startswith("USB") and item.hash_status
            ),
            None,
        )
        parts = [cable.hash_status, usb_hash]
        if cable.hash_status == usb_hash:
            parts = parts[:1]
        return Cell(" / ".join(part for part in parts if part) or "–", Style.DIM)

    rows = tuple(
        (
            Cell(port.name, Style.BOLD),
            _cable_cell(port),
            Cell(port.cable.authentication, Style.GREEN)
            if port.cable.attached and port.cable.authentication
            else _DIM,
            hash_cell(port),
            Cell(str(port.cable.pd_spec_revision), Style.DEFAULT)
            if port.cable.pd_spec_revision
            else _DIM,
            Cell(", ".join(port.power_in), Style.CYAN) if port.power_in else _DIM,
            Cell("detected", Style.RED) if port.liquid_detected else Cell("clean", Style.DIM),
            Cell(port.firmware, Style.DIM) if port.firmware else _DIM,
        )
        for port in snapshot.ports
    )
    return TableModel(columns, rows, empty_message="No cable or port controller data.")


def _device_rows(snapshot: Snapshot) -> tuple[tuple[Cell, ...], ...]:
    rows: list[tuple[Cell, ...]] = []
    for device in snapshot.devices:
        rows.append(
            (
                Cell(device.name, Style.BOLD),
                Cell(device.vendor, Style.DEFAULT) if device.vendor else _DIM,
                Cell(device.id_string, Style.DIM),
                Cell(device.mode.label, _mode_style(device.mode)),
                Cell(device.port, Style.CYAN) if device.port else _DIM,
                Cell(device.transport, Style.CYAN) if device.transport else _DIM,
                Cell(device.bus, Style.DIM) if device.bus else _DIM,
                Cell(device.serial, Style.DIM) if device.serial else _DIM,
                Cell("yes", Style.YELLOW) if device.restricted else Cell("no", Style.DIM),
            )
        )
    return tuple(rows)


def _devices_model(snapshot: Snapshot) -> TableModel:
    columns = (
        Column("name", "Device", 260, monospaced=False),
        Column("vendor", "Vendor", 130, monospaced=False),
        Column("id", "VID:PID", 110),
        Column("mode", "Mode", 200),
        Column("port", "Port", 100),
        Column("transport", "Transport", 100),
        Column("bus", "Bus", 140, monospaced=False),
        Column("serial", "Serial", 140),
        Column("restricted", "Restricted", 90, monospaced=False),
    )
    return TableModel(
        columns,
        _device_rows(snapshot),
        empty_message="No USB device attached — plug one in, the table refreshes itself.",
    )


def _thunderbolt_model(snapshot: Snapshot) -> TableModel:
    columns = (
        Column("bus", "Bus", 200, monospaced=False),
        Column("receptacle", "Receptacle", 100),
        Column("state", "State", 110, monospaced=False),
        Column("link", "Link", 140),
        Column("host", "Host / vendor", 200, monospaced=False),
    )
    rows = tuple(
        (
            Cell(port.bus, Style.BOLD),
            Cell(str(port.receptacle), Style.DEFAULT) if port.receptacle else _DIM,
            Cell("● connected", Style.GREEN) if port.connected else Cell("○ free", Style.DIM),
            Cell(port.speed, Style.CYAN) if port.speed else _DIM,
            Cell(" · ".join(part for part in (port.device, port.vendor) if part), Style.DIM)
            or _DIM,
        )
        for port in snapshot.thunderbolt
    )
    return TableModel(columns, rows, empty_message="No Thunderbolt/USB4 receptacle reported.")


def table_model(snapshot: Snapshot, view: str) -> TableModel:
    """Build the table model for ``view`` (one of :data:`VIEWS`)."""
    builders = {
        "ports": _ports_model,
        "cables": _cables_model,
        "devices": _devices_model,
        "thunderbolt": _thunderbolt_model,
    }
    try:
        builder = builders[view]
    except KeyError:
        raise ValueError(f"unknown view {view!r}; expected one of {', '.join(VIEWS)}") from None
    return builder(snapshot)


def header_text(snapshot: Snapshot) -> str:
    """Window title: model, chip and macOS version."""
    parts = [part for part in (snapshot.model, snapshot.chip) if part]
    if snapshot.os_version:
        parts.append(f"macOS {snapshot.os_version}")
    return f"usbscope — {' · '.join(parts) if parts else snapshot.host}"


def summary_text(snapshot: Snapshot) -> str:
    """One line of headline facts below the toolbar."""
    return (
        f"{len(snapshot.ports)} ports · {len(snapshot.connected_ports)} connected · "
        f"{len(snapshot.devices)} device(s) · {len(snapshot.emarked_cables)} e-marked cable(s) · "
        f"{len(snapshot.thunderbolt)} USB4 receptacle(s)"
    )


def status_text(snapshot: Snapshot, *, interval: float | None, reads: int) -> str:
    """Status bar line: last read, refresh cadence and source problems."""
    when = snapshot.seen_at.strftime("%H:%M:%S")
    parts = [f"Read at {when} (read #{reads})"]
    parts.append(f"auto-refresh {interval:g}s" if interval else "auto-refresh off")
    parts.append("system_profiler + ioreg -p IOPort")
    if snapshot.warnings:
        parts.append(f"{len(snapshot.warnings)} warning(s): {snapshot.warnings[0]}")
    return "  ·  ".join(parts)


def device_tooltip(device: UsbDevice) -> str:
    """Multi line tooltip for a device row."""
    lines = [device.label, f"ID: {device.id_string}"]
    if device.mode:
        lines.append(f"Link: {device.mode.label}")
    if device.port:
        lines.append(f"Port: {device.port} ({device.transport or 'unknown transport'})")
    if device.version:
        lines.append(f"Device version: {device.version}")
    if device.serial:
        lines.append(f"Serial: {device.serial}")
    if device.location_id:
        lines.append(f"Location ID: 0x{device.location_id:08x}")
    return "\n".join(lines)
