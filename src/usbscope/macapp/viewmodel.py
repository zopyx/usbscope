"""Presentation model for the macOS app.

Pure Python: it turns a :class:`~usbscope.models.Snapshot` into table models and
header/status strings. The AppKit layer only maps the style names onto
``NSColor``/fonts, which keeps the UI logic testable without a window server.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from ..models import Port, Snapshot, ThunderboltPort, UsbDevice, UsbMode
from .changes import (
    ADDED,
    CHANGED,
    REMOVED,
    ChangeSet,
    change_tag,
    device_key,
    diff_snapshots,
    port_key,
)

__all__ = [
    "ADDED",
    "CHANGED",
    "REMOVED",
    "VIEWS",
    "Align",
    "Cell",
    "ChangeSet",
    "Column",
    "Style",
    "TableModel",
    "apply_changes",
    "detail_pairs",
    "device_key",
    "device_tooltip",
    "diff_snapshots",
    "header_text",
    "port_key",
    "row_tooltip",
    "status_text",
    "summary_text",
    "table_model",
]

VIEWS = ("ports", "cables", "devices", "thunderbolt")


class Align(StrEnum):
    """Cell alignment, mapped to ``NSTextAlignment`` by the app layer."""

    LEFT = "left"
    RIGHT = "right"


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


_HIGHLIGHT_STYLE = {ADDED: Style.GREEN, REMOVED: Style.RED, CHANGED: Style.YELLOW}


@dataclass(frozen=True, slots=True)
class Column:
    """One table column."""

    key: str
    title: str
    width: float
    monospaced: bool = True
    align: Align = Align.LEFT
    sortable: bool = True


@dataclass(frozen=True, slots=True)
class Cell:
    """One table cell.

    ``sort_value`` is a hidden, better comparable stand-in for the visible text
    (a mode rank, a 0/1 flag, a bit rate); the table sorts by it when present.
    """

    text: str
    style: Style = Style.DEFAULT
    sort_value: object | None = None


@dataclass(frozen=True, slots=True)
class TableModel:
    """The table shown for one view."""

    columns: tuple[Column, ...]
    rows: tuple[tuple[Cell, ...], ...]
    empty_message: str = ""
    row_keys: tuple[str, ...] = ()
    row_highlights: tuple[Style | None, ...] = ()

    @property
    def row_count(self) -> int:
        """Number of rows."""
        return len(self.rows)

    def highlight(self, index: int) -> Style | None:
        """Row colour for a changed row, or ``None``."""
        if not self.row_highlights or index >= len(self.row_highlights):
            return None
        return self.row_highlights[index]

    def clipboard_text(self, *, column: int | None = None) -> str:
        """Tab separated text of the whole model (or of one column)."""
        from .tableops import to_tsv

        return to_tsv(self, column=column)


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
    if port.connected:
        return Cell("● connected", Style.GREEN, sort_value=1)
    return Cell("○ free", Style.DIM, sort_value=0)


def _mode_cell(port: Port) -> Cell:
    transport = port.usb_transport
    if transport is None or not transport.active:
        if port.connected:
            return Cell("no USB data", Style.YELLOW, sort_value=-1)
        return replace(_DIM, sort_value=-2)
    return Cell(transport.mode.label, _mode_style(transport.mode), sort_value=transport.mode.rank)


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
        return replace(_DIM, sort_value=0)
    return Cell(
        cable.kind,
        Style.CYAN if cable.emarker else Style.DIM,
        sort_value=2 if cable.emarker else 1,
    )


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
            Cell(
                port.name,
                Style.BOLD,
                sort_value=port.number if port.number is not None else 999,
            ),
            Cell(port.kind, Style.DIM if port.kind in {"HDMI", "SD Card"} else Style.DEFAULT),
            _state_cell(port),
            _mode_cell(port),
            _transports_cell(port),
            _cable_cell(port),
            _notes_cell(port),
        )
        for port in snapshot.ports
    )
    return TableModel(
        columns,
        rows,
        empty_message="No ports reported by the port controller.",
        row_keys=tuple(port_key(port) for port in snapshot.ports),
    )


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
            Cell(port.name, Style.BOLD, sort_value=port.number if port.number is not None else 999),
            _cable_cell(port),
            Cell(port.cable.authentication, Style.GREEN, sort_value=1)
            if port.cable.attached and port.cable.authentication
            else replace(_DIM, sort_value=0),
            hash_cell(port),
            Cell(
                str(port.cable.pd_spec_revision),
                Style.DEFAULT,
                sort_value=port.cable.pd_spec_revision,
            )
            if port.cable.pd_spec_revision
            else replace(_DIM, sort_value=0),
            Cell(", ".join(port.power_in), Style.CYAN) if port.power_in else _DIM,
            Cell("detected", Style.RED, sort_value=1)
            if port.liquid_detected
            else Cell("clean", Style.DIM, sort_value=0),
            Cell(port.firmware, Style.DIM) if port.firmware else _DIM,
        )
        for port in snapshot.ports
    )
    return TableModel(
        columns,
        rows,
        empty_message="No cable or port controller data.",
        row_keys=tuple(port_key(port) for port in snapshot.ports),
    )


def thunderbolt_key(port: ThunderboltPort) -> str:
    """Row key of a Thunderbolt receptacle."""
    return f"tb:{port.bus}:{port.receptacle if port.receptacle is not None else '-'}"


def _device_rows(snapshot: Snapshot) -> tuple[tuple[Cell, ...], ...]:
    rows: list[tuple[Cell, ...]] = []
    for device in snapshot.devices:
        rows.append(
            (
                Cell(device.name, Style.BOLD),
                Cell(device.vendor, Style.DEFAULT) if device.vendor else _DIM,
                Cell(device.id_string, Style.DIM),
                Cell(device.mode.label, _mode_style(device.mode), sort_value=device.mode.rank),
                Cell(device.port, Style.CYAN) if device.port else _DIM,
                Cell(device.transport, Style.CYAN) if device.transport else _DIM,
                Cell(device.bus, Style.DIM) if device.bus else _DIM,
                Cell(device.serial, Style.DIM) if device.serial else _DIM,
                Cell("yes", Style.YELLOW, sort_value=1)
                if device.restricted
                else Cell("no", Style.DIM, sort_value=0),
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
        row_keys=tuple(device_key(device) for device in snapshot.devices),
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
            Cell(str(port.receptacle), Style.DEFAULT, sort_value=port.receptacle)
            if port.receptacle
            else _DIM,
            Cell("● connected", Style.GREEN, sort_value=1)
            if port.connected
            else Cell("○ free", Style.DIM, sort_value=0),
            Cell(port.speed, Style.CYAN) if port.speed else _DIM,
            Cell(" · ".join(part for part in (port.device, port.vendor) if part), Style.DIM)
            or _DIM,
        )
        for port in snapshot.thunderbolt
    )
    return TableModel(
        columns,
        rows,
        empty_message="No Thunderbolt/USB4 receptacle reported.",
        row_keys=tuple(thunderbolt_key(port) for port in snapshot.thunderbolt),
    )


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


def status_text(
    snapshot: Snapshot,
    *,
    interval: float | None,
    reads: int,
    changes: ChangeSet | None = None,
    filter_query: str = "",
) -> str:
    """Status bar line: last read, cadence, changes and source problems."""
    when = snapshot.seen_at.strftime("%H:%M:%S")
    parts = [f"Read at {when} (read #{reads})"]
    parts.append(f"auto-refresh {interval:g}s" if interval else "auto-refresh off")
    parts.append("system_profiler + ioreg -p IOPort")
    if changes is not None and not changes.is_empty:
        parts.append(f"changed: {changes.summary()}")
    if filter_query:
        parts.append(f"filter: {filter_query!r}")
    if snapshot.warnings:
        parts.append(f"{len(snapshot.warnings)} warning(s): {snapshot.warnings[0]}")
    return "  ·  ".join(parts)


def apply_changes(model: TableModel, changes: ChangeSet | None) -> TableModel:
    """Return ``model`` with per-row highlights derived from ``changes``.

    Appeared rows turn green, disappeared rows red and rows whose port state
    changed yellow; everything else stays uncoloured.
    """
    if changes is None or not model.row_keys:
        return model
    highlights = tuple(
        _HIGHLIGHT_STYLE.get(change_tag(changes, key) or "") for key in model.row_keys
    )
    return replace(model, row_highlights=highlights)


def _pair(label: str, value: object) -> tuple[str, str] | None:
    """One label/value pair, dropped when the value is unknown."""
    if value is None or value == "" or value == () or value == []:
        return None
    if isinstance(value, bool):
        return label, "yes" if value else "no"
    return label, str(value)


def _pairs(*items: tuple[str, str] | None) -> tuple[tuple[str, str], ...]:
    return tuple(item for item in items if item is not None)


def port_details(port: Port) -> tuple[tuple[str, str], ...]:
    """Every known fact about a port, as label/value pairs."""
    transport = port.usb_transport
    cable = port.cable
    transfers = " · ".join(
        f"{item.kind} {'active' if item.active else 'idle'}" for item in port.transports
    )
    return _pairs(
        _pair("Port", port.name),
        _pair("Description", port.description),
        _pair("Type", port.kind),
        _pair("Connected", port.connected),
        _pair("Number", port.number),
        _pair("Connect type", port.connect_type),
        _pair("USB link", transport.mode.label if transport is not None else None),
        _pair("USB link active", transport.active if transport is not None else None),
        _pair("USB speed", transport.rate_text if transport is not None else None),
        _pair("Super speed active", port.super_speed_active),
        _pair("Transports", transfers),
        _pair("Cable", cable.kind if cable.attached else None),
        _pair("e-marker", cable.emarker if cable.attached else None),
        _pair("Cable authentication", cable.authentication),
        _pair("Cable hash", cable.hash_status),
        _pair("PD specification", cable.pd_spec_revision),
        _pair("Power in", ", ".join(port.power_in)),
        _pair("Liquid detected", port.liquid_detected),
        _pair("Authorization", port.authorization),
        _pair("Controller firmware", port.firmware),
        _pair("DisplayPort pin assignment", port.displayport_pin_assignment),
        _pair("Plug orientation", port.plug_orientation),
        _pair(
            "Devices", ", ".join(f"{device.name} ({device.id_string})" for device in port.devices)
        ),
    )


def cable_details(port: Port) -> tuple[tuple[str, str], ...]:
    """Cable/port-controller facts (the cables view) as label/value pairs."""
    cable = port.cable
    usb = port.usb_transport
    return _pairs(
        _pair("Port", port.name),
        _pair("Cable", cable.kind if cable.attached else None),
        _pair("e-marker", cable.emarker if cable.attached else None),
        _pair("Active cable", cable.active if cable.attached else None),
        _pair("Optical", cable.optical if cable.attached else None),
        _pair("CC authentication", cable.authentication),
        _pair("Cable hash", cable.hash_status),
        _pair("USB3 hash", usb.hash_status if usb is not None else None),
        _pair("PD specification", cable.pd_spec_revision),
        _pair("Power in", ", ".join(port.power_in)),
        _pair("Liquid detected", port.liquid_detected),
        _pair("Authorization", port.authorization),
        _pair("Controller firmware", port.firmware),
    )


def device_details(device: UsbDevice) -> tuple[tuple[str, str], ...]:
    """Every known fact about a device as label/value pairs."""
    return _pairs(
        _pair("Device", device.label),
        _pair("Vendor", device.vendor),
        _pair("VID:PID", device.id_string),
        _pair("USB link", device.mode.label),
        _pair("Speed", device.speed_text),
        _pair("Mode (bit/s)", device.speed_mbps),
        _pair("Port", device.port),
        _pair("Port type", device.port_type),
        _pair("Transport", device.transport),
        _pair("Bus", device.bus),
        _pair("Connection", device.connection),
        _pair("Device version", device.version),
        _pair("Generation", device.generation),
        _pair("Serial", device.serial),
        _pair("Location ID", f"0x{device.location_id:08x}" if device.location_id else None),
        _pair("Restricted by macOS", device.restricted),
        _pair("Source", device.source),
    )


def thunderbolt_details(port: ThunderboltPort) -> tuple[tuple[str, str], ...]:
    """Thunderbolt receptacle facts as label/value pairs."""
    return _pairs(
        _pair("Bus", port.bus),
        _pair("Receptacle", port.receptacle),
        _pair("Connected", port.connected),
        _pair("Status", port.status),
        _pair("Link", port.speed),
        _pair("Device", port.device),
        _pair("Vendor", port.vendor),
    )


def details_for_key(snapshot: Snapshot, key: str) -> tuple[tuple[str, str], ...]:
    """Detail pairs for the object a table row stands for.

    Keyed by :attr:`TableModel.row_keys`, so it survives sorting and filtering.
    """
    if key.startswith("device:"):
        for device in snapshot.devices:
            if device_key(device) == key:
                return device_details(device)
    elif key.startswith("tb:"):
        for port in snapshot.thunderbolt:
            if thunderbolt_key(port) == key:
                return thunderbolt_details(port)
    elif key.startswith("port:"):
        name = key.removeprefix("port:")
        for port in snapshot.ports:
            if port.name == name:
                return port_details(port)
    return ()


def detail_pairs(snapshot: Snapshot, view: str, row_key: str) -> tuple[tuple[str, str], ...]:
    """Detail pairs for a row of ``view`` (the cables view shows cable facts)."""
    if view == "cables":
        name = row_key.removeprefix("port:")
        for port in snapshot.ports:
            if port.name == name:
                return cable_details(port)
        return ()
    return details_for_key(snapshot, row_key)


def row_tooltip(snapshot: Snapshot, view: str, row_key: str) -> str:
    """Multi line tooltip for any row, not just device rows."""
    pairs = detail_pairs(snapshot, view, row_key)
    return "\n".join(f"{label}: {value}" for label, value in pairs)


def device_tooltip(device: UsbDevice) -> str:
    """Multi line tooltip for a device row."""
    return "\n".join(f"{label}: {value}" for label, value in device_details(device))
