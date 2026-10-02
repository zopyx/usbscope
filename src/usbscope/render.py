"""Rich rendering of a :class:`~usbscope.models.Snapshot`.

Only this module knows about colours, boxes and emojis - the domain model stays
presentation free so that tests can assert on data instead of ANSI codes.

The port table adapts to the terminal width: narrow terminals drop the
transport and cable columns and fold their content into the notes column, so
nothing is ever lost, only compacted.
"""

from __future__ import annotations

from rich import box
from rich.console import Console, Group, RenderableType
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich.tree import Tree

from .models import Port, Snapshot, Transport, UsbDevice, UsbMode

__all__ = ["render"]

WIDE_WIDTH = 118
MEDIUM_WIDTH = 92

_ICONS: tuple[tuple[tuple[str, ...], str], ...] = (
    (("yubikey", "fido", "security key", "smartcard", "smart card"), "🔐"),
    (("keyboard", "tastatur"), "⌨️"),
    (("mouse", "maus", "trackpad", "trackball"), "🖱️"),
    (("hub", "docking", "dock"), "🔀"),
    (("ssd", "disk", "storage", "drive", "flash", "mass storage"), "💾"),
    (("camera", "webcam", "facetime"), "📷"),
    (("audio", "headset", "headphone", "speaker", "microphone", "mic"), "🎧"),
    (("iphone", "ipad", "phone", "pixel", "galaxy"), "📱"),
    (("ethernet", "network", "lan", "wifi"), "🌐"),
    (("display", "monitor", "screen"), "🖥️"),
    (("card reader", "sd"), "🗂️"),
    (("gamepad", "controller", "joystick"), "🎮"),
    (("printer", "scanner"), "🖨️"),
)

_MODE_STYLES: tuple[tuple[int, str], ...] = (
    (7, "bold magenta"),
    (4, "cyan"),
    (3, "bold green"),
    (1, "yellow"),
)

_NON_USB_KINDS = {"HDMI", "SD Card"}


def _icon(device: UsbDevice) -> str:
    haystack = f"{device.name} {device.vendor or ''}".lower()
    for needles, icon in _ICONS:
        if any(needle in haystack for needle in needles):
            return icon
    return "🔹"


def _mode_style(mode: UsbMode) -> str:
    for threshold, style in _MODE_STYLES:
        if mode.rank >= threshold:
            return style
    return "dim"


def _short_kind(kind: str) -> str:
    return {"DisplayPort": "DP", "CC": "CC"}.get(kind, kind.upper())


def _transport_detail(transport: Transport) -> str | None:
    parts = [part for part in (transport.rate_text, transport.signaling) if part]
    if transport.lanes:
        parts.append(f"{transport.lanes} lanes")
    if transport.data_role:
        parts.append(transport.data_role.lower())
    return ", ".join(parts) or None


def _restricted_transports(port: Port) -> list[Transport]:
    """Only active transports can actually be restricted by macOS."""
    return [item for item in port.transports if item.restricted and item.active]


def _state_text(port: Port) -> Text:
    if port.connected:
        return Text("● connected", style="bold green")
    return Text("○ free", style="dim")


def _mode_text(port: Port, *, full: bool) -> Text:
    transport = port.usb_transport
    if transport is None or not transport.active:
        if port.connected:
            return Text("no USB data", style="yellow")
        return Text("–", style="dim")
    mode = transport.mode
    return Text(mode.label if full else mode.short, style=_mode_style(mode))


def _transports_text(port: Port, verbose: bool) -> Text:
    if not port.transports:
        return Text("–", style="dim")
    text = Text()
    for index, transport in enumerate(port.transports):
        if index:
            text.append(" · ", style="dim")
        style = "green" if transport.active else "dim"
        text.append(
            f"{_short_kind(transport.kind)} {'●' if transport.active else '○'}", style=style
        )
        if verbose and transport.active and (detail := _transport_detail(transport)):
            text.append(f" ({detail})", style="dim")
    return text


def _cable_text(port: Port, verbose: bool) -> Text:
    cable = port.cable
    if not cable.attached:
        return Text("–", style="dim")
    style = "cyan" if cable.emarker else "dim"
    text = Text(cable.kind, style=style)
    if verbose:
        details = [
            detail
            for detail in (
                f"CC auth: {cable.authentication}" if cable.authentication else None,
                f"CC hash: {cable.hash_status}" if cable.hash_status else None,
                f"PD spec {cable.pd_spec_revision}" if cable.pd_spec_revision else None,
            )
            if detail
        ]
        if details:
            text.append(" (" + ", ".join(details) + ")", style="dim")
    return text


def _notes(port: Port, verbose: bool, level: str) -> list[tuple[str, str]]:
    """Notes as ``(text, style)`` pairs; ``level`` is wide/medium/narrow."""
    notes: list[tuple[str, str]] = []
    if not port.connected and not port.devices:
        return notes
    if port.devices:
        names = ", ".join(device.name for device in port.devices)
        count = f"{len(port.devices)} device(s)"
        notes.append((f"{count}: {names}" if level == "wide" else count, "white"))
    if level == "narrow" and port.transports:
        active = [item.kind for item in port.transports if item.active]
        notes.append((f"link: {', '.join(active) or 'none'}", "dim"))
    if level != "wide":
        cable = port.cable
        notes.append(("cable: " + cable.kind, "cyan" if cable.emarker else "dim"))
    displayport = port.transport("DisplayPort")
    if displayport is not None and displayport.active:
        detail = _transport_detail(displayport)
        notes.append((f"DP alt mode{': ' + detail if detail else ''}", "cyan"))
    if port.power_in:
        notes.append(("power in: " + ", ".join(port.power_in), "cyan"))
    if port.connected and port.usb_transport is None:
        notes.append(("charge/accessory only, no USB data transport", "yellow"))
    if port.liquid_detected:
        notes.append(("liquid detected", "bold red"))
    if port.authorization and port.authorization not in {"Not Required", "No Action"}:
        notes.append((f"authorization: {port.authorization}", "yellow"))
    if _restricted_transports(port):
        notes.append(("restricted by macOS", "yellow"))
    if verbose:
        if port.super_speed_active is not None:
            notes.append((f"superspeed: {'yes' if port.super_speed_active else 'no'}", "dim"))
        if port.plug_orientation is not None:
            notes.append((f"plug orientation: {port.plug_orientation}", "dim"))
        if port.firmware:
            notes.append((f"controller fw {port.firmware}", "dim"))
        for transport in port.transports:
            if transport.active and transport.trm_state:
                profile = f" ({transport.trm_profile})" if transport.trm_profile else ""
                notes.append((f"TRM {transport.kind}: {transport.trm_state}{profile}", "dim"))
    return notes


def _notes_text(port: Port, verbose: bool, level: str) -> Text:
    text = Text()
    for note, style in _notes(port, verbose, level):
        if text:
            text.append(" · ", style="dim")
        text.append(note, style=style)
    return text if text else Text("–", style="dim")


def _ports_table(snapshot: Snapshot, verbose: bool, width: int) -> Table:
    level = "wide" if width >= WIDE_WIDTH else "medium" if width >= MEDIUM_WIDTH else "narrow"
    table = Table(
        box=box.ROUNDED,
        header_style="bold white",
        border_style="grey37",
        title="Ports & cables",
        title_justify="left",
        title_style="bold",
    )
    table.add_column("Port", no_wrap=True)
    table.add_column("Type", no_wrap=True)
    table.add_column("State", no_wrap=True)
    table.add_column("Mode", overflow="fold")
    if level == "wide":
        table.add_column("Transports", overflow="fold")
        table.add_column("Cable", overflow="fold")
    elif level == "medium":
        table.add_column("Transports", overflow="fold")
    table.add_column("Notes", overflow="fold")

    for port in snapshot.ports:
        row = [
            Text(port.name, style="bold"),
            Text(port.kind, style="dim" if port.kind in _NON_USB_KINDS else "white"),
            _state_text(port),
            _mode_text(port, full=level == "wide"),
        ]
        if level == "wide":
            row.append(_transports_text(port, verbose))
            row.append(_cable_text(port, verbose))
        elif level == "medium":
            row.append(_transports_text(port, verbose))
        row.append(_notes_text(port, verbose, level))
        table.add_row(*row)
    return table


def _device_line(device: UsbDevice, verbose: bool) -> Text:
    text = Text()
    text.append(f"{_icon(device)} ")
    text.append(device.label, style="bold white")
    text.append(f"  {device.id_string}", style="dim")
    text.append("  ")
    text.append(device.mode.label, style=_mode_style(device.mode))
    if device.serial:
        text.append(f"  serial {device.serial}", style="dim")
    if device.version:
        text.append(f"  hw {device.version}", style="dim")
    if device.port:
        text.append(f"  → {device.port}", style="cyan")
        if device.transport:
            text.append(f" via {device.transport}", style="cyan")
    if device.restricted:
        text.append("  restricted by macOS", style="yellow")
    if verbose:
        for key, value in (
            ("location", f"0x{device.location_id:08x}" if device.location_id else None),
            ("connection", device.connection),
            ("generation", device.generation),
            ("source", device.source),
        ):
            if value:
                text.append(f"  {key}={value}", style="dim")
    return text


def _devices_tree(snapshot: Snapshot, verbose: bool) -> Tree:
    tree = Tree(Text(f"Devices ({len(snapshot.devices)})", style="bold"), guide_style="grey37")
    for bus in snapshot.buses:
        heading = Text(bus.name, style="bold white")
        if bus.driver:
            heading.append(f"  {bus.driver}", style="dim")
        if bus.location_id is not None:
            heading.append(f"  @0x{bus.location_id:08x}", style="dim")
        node = tree.add(heading)
        if not bus.devices:
            node.add(Text("no devices", style="dim"))
            continue
        for device in bus.devices:
            node.add(_device_line(device, verbose))
    if not snapshot.buses:
        tree.add(Text("no USB buses reported", style="dim"))
    return tree


def _thunderbolt_table(snapshot: Snapshot, verbose: bool) -> Table:
    table = Table(
        box=box.ROUNDED,
        header_style="bold white",
        border_style="grey37",
        title="Thunderbolt / USB4 receptacles",
        title_justify="left",
        title_style="bold",
    )
    table.add_column("Bus", no_wrap=True)
    table.add_column("Port", no_wrap=True)
    table.add_column("State", no_wrap=True)
    table.add_column("Link", no_wrap=True)
    if verbose:
        table.add_column("Host / vendor", overflow="fold")
    for receptacle in snapshot.thunderbolt:
        state = (
            Text("● connected", style="bold green")
            if receptacle.connected
            else Text("○ free", style="dim")
        )
        row = [
            Text(receptacle.bus, style="bold"),
            Text(str(receptacle.receptacle) if receptacle.receptacle is not None else "–"),
            state,
            Text(receptacle.speed or "–", style="cyan"),
        ]
        if verbose:
            row.append(
                Text(
                    " · ".join(part for part in (receptacle.device, receptacle.vendor) if part)
                    or "–",
                    style="dim",
                )
            )
        table.add_row(*row)
    return table


def _cables_panel(snapshot: Snapshot, verbose: bool) -> RenderableType:
    table = Table(
        box=box.ROUNDED,
        header_style="bold white",
        border_style="grey37",
        title="Cable & port controller",
        title_justify="left",
        title_style="bold",
    )
    for column in ("Port", "Cable", "CC authentication", "Hash (CC / USB)", "PD spec"):
        table.add_column(column, overflow="fold")
    if verbose:
        for column in ("Power in", "Liquid", "Accessory allowed", "Controller fw"):
            table.add_column(column, overflow="fold")
    for port in snapshot.ports:
        cable = port.cable
        # the accessory hash that macOS cached for the USB link of this port
        usb_hash = next(
            (
                item.hash_status
                for item in port.transports
                if item.kind.upper().startswith("USB") and item.hash_status
            ),
            None,
        )
        parts = [part for part in (cable.hash_status, usb_hash) if part] if cable.attached else []
        if parts and cable.hash_status == usb_hash:
            parts = parts[:1]
        hash_cell = " / ".join(parts) if parts else "–"
        attached = cable.attached
        row = [
            Text(port.name, style="bold"),
            Text(cable.kind, style="cyan" if cable.emarker else "dim"),
            Text(
                (cable.authentication or "–") if attached else "–",
                style="green" if attached else "dim",
            ),
            Text(hash_cell, style="dim"),
            Text(str(cable.pd_spec_revision) if cable.pd_spec_revision else "–"),
        ]
        if verbose:
            row.extend(
                [
                    Text(", ".join(port.power_in) or "–", style="cyan"),
                    Text(
                        "detected" if port.liquid_detected else "clean",
                        style="red" if port.liquid_detected else "dim",
                    ),
                    Text(
                        port.authorization or "–",
                        style="yellow"
                        if port.authorization not in {"Not Required", "No Action"}
                        else "dim",
                    ),
                    Text(port.firmware or "–", style="dim"),
                ]
            )
        table.add_row(*row)
    return table


def _summary_panel(snapshot: Snapshot, refresh: int | None) -> Panel:
    machine = " · ".join(
        part for part in (snapshot.model, snapshot.chip, f"macOS {snapshot.os_version}") if part
    )
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column()
    grid.add_row("Machine", Text(machine, style="bold white"))
    grid.add_row("Host", Text(snapshot.host))
    grid.add_row(
        "Ports",
        Text(
            f"{len(snapshot.ports)} total · {len(snapshot.connected_ports)} connected · "
            f"{len(snapshot.emarked_cables)} e-marked cable(s)"
        ),
    )
    grid.add_row("Devices", Text(str(len(snapshot.devices))))
    if snapshot.thunderbolt:
        connected = sum(1 for port in snapshot.thunderbolt if port.connected)
        grid.add_row(
            "USB4/TB", Text(f"{len(snapshot.thunderbolt)} receptacle(s) · {connected} connected")
        )
    grid.add_row("Read at", Text(snapshot.seen_at.strftime("%Y-%m-%d %H:%M:%S"), style="dim"))
    subtitle = f"[dim]refresh {refresh} · Ctrl-C to quit[/]" if refresh is not None else None
    return Panel(
        grid,
        title="[bold]usbscope[/] [dim]— macOS USB inspector[/]",
        subtitle=subtitle,
        border_style="cyan",
        box=box.ROUNDED,
    )


def _footer(console: Console, snapshot: Snapshot, verbose: bool) -> RenderableType:
    lines: list[RenderableType] = []
    legend = Text()
    legend.append("●", style="green")
    legend.append(" active   ", style="dim")
    legend.append("○", style="dim")
    legend.append(" idle   ", style="dim")
    legend.append("–", style="dim")
    legend.append(" not present / unknown", style="dim")
    lines.append(legend)
    modes = sorted({port.mode for port in snapshot.ports if port.mode != UsbMode.UNKNOWN})
    if modes and console.width < WIDE_WIDTH:
        lines.append(
            Text.from_markup(
                "[dim]modes:[/] "
                + " · ".join(f"[{_mode_style(mode)}]{mode.short}[/]" for mode in modes)
                + "[dim] ("
                + ", ".join(mode.label for mode in modes)
                + ")[/]"
            )
        )
    if not verbose:
        lines.append(
            Text.from_markup(
                "[dim]hint:[/] [cyan]usbscope --watch 2[/] [dim]live refresh ·[/] "
                "[cyan]usbscope -v[/] [dim]more detail ·[/] [cyan]usbscope --json[/] "
                "[dim]machine readable[/]"
            )
        )
    return Group(*lines)


def _warnings(snapshot: Snapshot) -> RenderableType | None:
    if not snapshot.warnings:
        return None
    body = Group(*[Text(f"• {warning}", style="yellow") for warning in snapshot.warnings])
    return Panel(body, title="[yellow]notes[/]", border_style="yellow", box=box.ROUNDED)


def _empty_devices_hint(snapshot: Snapshot) -> RenderableType | None:
    if snapshot.devices:
        return None
    return Text.from_markup(
        "[dim]No USB device is attached right now — plug one in and use "
        "[cyan]usbscope --watch 2[/] to watch the ports negotiate.[/]"
    )


def build_view(
    snapshot: Snapshot,
    console: Console,
    *,
    view: str = "overview",
    verbose: bool = False,
    refresh: int | None = None,
) -> RenderableType:
    """Assemble the requested view as a single renderable.

    Returning (instead of printing) keeps one-shot output and the flicker free
    live mode of ``--watch`` on the same code path.
    """
    parts: list[RenderableType] = [_summary_panel(snapshot, refresh)]
    if (warnings := _warnings(snapshot)) is not None:
        parts.append(warnings)
    if view in {"overview", "ports"} and snapshot.ports:
        parts.append(_ports_table(snapshot, verbose, console.width))
    if view == "cables":
        parts.append(_cables_panel(snapshot, verbose))
    if view in {"overview", "ports"} and (hint := _empty_devices_hint(snapshot)) is not None:
        parts.append(hint)
    if view in {"overview", "devices"}:
        parts.append(_devices_tree(snapshot, verbose))
    if view in {"overview", "thunderbolt"} and snapshot.thunderbolt:
        parts.append(_thunderbolt_table(snapshot, verbose))
    if view in {"overview", "ports", "cables"}:
        parts.append(_footer(console, snapshot, verbose))
    return Group(*parts)


def render(
    snapshot: Snapshot,
    console: Console,
    *,
    view: str = "overview",
    verbose: bool = False,
    refresh: int | None = None,
) -> None:
    """Print the requested view of ``snapshot`` to ``console``."""
    console.print(build_view(snapshot, console, view=view, verbose=verbose, refresh=refresh))
