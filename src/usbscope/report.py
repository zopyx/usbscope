"""Human readable report (``usbscope report``) as Markdown or self-contained HTML.

``usbscope report`` is the artefact a person reads (or attaches to a ticket):
machine, port table, devices with class/tier, cables, the per-port power
contract, the live charging numbers, the security findings and the collection
warnings. It renders the *same* facts as the terminal views, but as a document
that survives copy/paste.

Two formats, both built from the same section list so Markdown and HTML can never
disagree:

* ``md`` (default) — a plain Markdown document with GitHub-style tables;
* ``html`` — one self-contained page with an inline stylesheet. No external
  assets and no network access, so it opens offline from ``file://``.

The renderer is pure (:func:`render_markdown` / :func:`render_html` take a
snapshot plus an already collected security report and storage inventory), which
is what makes it unit-testable and byte-for-byte reproducible across the Python
and Swift implementations.
"""

from __future__ import annotations

import html
from collections.abc import Sequence
from datetime import datetime

from .format import charger_flags, charging_state, power_line, watts
from .models import Port, Snapshot
from .security import SecurityReport, analyse
from .sources.storage import StorageDevice

__all__ = ["render_html", "render_markdown"]

_ABSENT = "–"
_NONE = "_none_"


def _timestamp(moment: datetime) -> str:
    """Naive local timestamp, identical to the snapshot ``seen_at`` serialisation."""
    return moment.isoformat(timespec="seconds")


def _machine(snapshot: Snapshot) -> str:
    parts = [
        part for part in (snapshot.model, snapshot.chip, f"macOS {snapshot.os_version}") if part
    ]
    return " · ".join(parts)


def _mode_cell(port: Port) -> str:
    """Negotiated mode of a port, or the absent glyph when no USB link is up."""
    transport = port.usb_transport
    if transport is None or not transport.active:
        return _ABSENT
    return transport.mode.label


def _devices_cell(port: Port) -> str:
    return ", ".join(device.name for device in port.devices) if port.devices else _ABSENT


def _port_rows(snapshot: Snapshot) -> tuple[tuple[str, ...], ...]:
    return tuple(
        (
            port.name,
            port.kind,
            "connected" if port.connected else "free",
            _mode_cell(port),
            port.cable.kind,
            _devices_cell(port),
        )
        for port in snapshot.ports
    )


def _device_rows(snapshot: Snapshot) -> tuple[tuple[str, ...], ...]:
    return tuple(
        (
            device.label,
            device.id_string,
            device.class_text or _ABSENT,
            str(device.tier) if device.tier is not None else _ABSENT,
            device.mode.label,
            device.port or _ABSENT,
        )
        for device in snapshot.devices
    )


def _cable_rows(snapshot: Snapshot) -> tuple[tuple[str, ...], ...]:
    rows: list[tuple[str, ...]] = []
    for port in snapshot.ports:
        cable = port.cable
        contract = port.power_contract
        rows.append(
            (
                port.name,
                cable.kind,
                (cable.authentication or _ABSENT) if cable.attached else _ABSENT,
                str(cable.pd_spec_revision) if cable.pd_spec_revision is not None else _ABSENT,
                ", ".join(port.power_in) if port.power_in else _ABSENT,
                contract.label if contract is not None else _ABSENT,
            )
        )
    return tuple(rows)


def _charging_lines(snapshot: Snapshot) -> tuple[str, ...]:
    charging = snapshot.charging
    if charging is None:
        return ("_no charging telemetry reported_",)
    entries: tuple[tuple[str, str | None], ...] = (
        ("State", charging_state(charging)),
        (
            "Adapter",
            power_line(
                charging.adapter_power_mw,
                charging.adapter_voltage_mv,
                charging.adapter_current_ma,
                compact=True,
            ),
        ),
        (
            "From adapter",
            power_line(
                charging.system_power_in_mw,
                charging.system_voltage_in_mv,
                charging.system_current_in_ma,
            ),
        ),
        ("System load", watts(charging.system_load_mw)),
        (
            "Battery",
            power_line(
                charging.battery_power_mw,
                charging.battery_voltage_mv,
                charging.battery_current_ma,
            ),
        ),
        ("Adapter loss", watts(charging.adapter_efficiency_loss_mw)),
        ("Charger", charger_flags(charging)),
    )
    return tuple(f"- {label}: {value}" for label, value in entries if value)


def _finding_rows(report: SecurityReport) -> tuple[tuple[str, ...], ...]:
    return tuple(
        (finding.severity.value, finding.rule, finding.subject, finding.detail)
        for finding in report.findings
    )


def _storage_rows(storage: Sequence[StorageDevice]) -> tuple[tuple[str, ...], ...]:
    return tuple(
        (
            device.identifier,
            device.label,
            device.capacity_text or _ABSENT,
            "read-only"
            if device.read_only is True
            else ("read/write" if device.read_only is False else _ABSENT),
            device.mount_point or _ABSENT,
        )
        for device in storage
    )


PORT_HEADERS = ("Port", "Type", "State", "Mode", "Cable", "Devices")
DEVICE_HEADERS = ("Device", "ID", "Class", "Tier", "Mode", "Port")
CABLE_HEADERS = ("Port", "Cable", "CC authentication", "PD spec", "Power in", "Contract")
FINDING_HEADERS = ("Severity", "Rule", "Subject", "Why")
STORAGE_HEADERS = ("Device", "Name", "Capacity", "Mode", "Mount")


def _sections(
    snapshot: Snapshot, report: SecurityReport, storage: Sequence[StorageDevice]
) -> tuple[tuple[str, tuple[tuple[str, ...], ...], tuple[str, ...]], ...]:
    """The shared content of both formats: (heading, table rows, extra lines)."""
    findings = _finding_rows(report)
    storage_rows = _storage_rows(storage)
    return (
        (
            "Ports",
            _port_rows(snapshot),
            ("_no receptacles reported_",) if not snapshot.ports else (),
        ),
        (
            "Devices",
            _device_rows(snapshot),
            ("_no USB devices attached_",) if not snapshot.devices else (),
        ),
        ("Cables", _cable_rows(snapshot), ()),
        ("Power", (), _charging_lines(snapshot)),
        (
            "Security findings",
            findings,
            ("_nothing stood out in what macOS reports_",) if not findings else (),
        ),
        (
            "USB mass storage",
            storage_rows,
            ("_no USB mass storage attached_",) if not storage_rows else (),
        ),
        ("Warnings", (), tuple(f"- {warning}" for warning in snapshot.warnings) or (_NONE,)),
    )


def _md_cell(value: str) -> str:
    """Escape a Markdown table cell (pipes break the table)."""
    return value.replace("|", "\\|").replace("\n", " ")


def _md_table(headers: Sequence[str], rows: Sequence[tuple[str, ...]]) -> tuple[str, ...]:
    head = "| " + " | ".join(headers) + " |"
    rule = "| " + " | ".join("---" for _ in headers) + " |"
    body = ["| " + " | ".join(_md_cell(cell) for cell in row) + " |" for row in rows]
    return (head, rule, *body)


def render_markdown(
    snapshot: Snapshot,
    report: SecurityReport | None = None,
    storage: Sequence[StorageDevice] = (),
) -> str:
    """Render the report as a Markdown document (trailing newline included)."""
    report = report if report is not None else analyse(snapshot)
    lines: list[str] = ["# usbscope report", ""]
    lines.append(f"- Machine: {_machine(snapshot)}")
    lines.append(f"- Host: {snapshot.host}")
    lines.append(f"- Read at: {_timestamp(snapshot.seen_at)}")
    lines.append(
        f"- Ports: {len(snapshot.ports)} total · {len(snapshot.connected_ports)} connected · "
        f"{len(snapshot.emarked_cables)} e-marked cable(s)"
    )
    lines.append(f"- Devices: {len(snapshot.devices)}")
    for title, rows, extra in _sections(snapshot, report, storage):
        lines.append("")
        lines.append(f"## {title}")
        lines.append("")
        headers = {
            "Ports": PORT_HEADERS,
            "Devices": DEVICE_HEADERS,
            "Cables": CABLE_HEADERS,
            "Security findings": FINDING_HEADERS,
            "USB mass storage": STORAGE_HEADERS,
        }.get(title)
        if headers is not None:
            lines.extend(_md_table(headers, rows))
        lines.extend(extra)
    return "\n".join(lines).rstrip("\n") + "\n"


def _esc(value: str) -> str:
    """HTML-escape a value (both quote styles), matching the Swift twin."""
    return html.escape(value, quote=True)


def _html_table(headers: Sequence[str], rows: Sequence[tuple[str, ...]]) -> tuple[str, ...]:
    out = [
        "<table>",
        "<thead><tr>" + "".join(f"<th>{_esc(h)}</th>" for h in headers) + "</tr></thead>",
    ]
    out.append("<tbody>")
    for row in rows:
        out.append("<tr>" + "".join(f"<td>{_esc(cell)}</td>" for cell in row) + "</tr>")
    out.append("</tbody>")
    out.append("</table>")
    return tuple(out)


def render_html(
    snapshot: Snapshot,
    report: SecurityReport | None = None,
    storage: Sequence[StorageDevice] = (),
) -> str:
    """Render the report as one self-contained HTML page (inline CSS, no assets)."""
    report = report if report is not None else analyse(snapshot)
    lines: list[str] = [
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        "<title>usbscope report</title>",
        "<style>",
        ":root { color-scheme: light dark; }",
        (
            'body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; '
            "margin: 2rem auto; max-width: 960px; padding: 0 1rem; "
            "color: #1b1b1b; background: #fff; }"
        ),
        "h1 { font-size: 1.6rem; }",
        (
            "h2 { font-size: 1.15rem; margin-top: 2rem; border-bottom: 1px solid #ddd; "
            "padding-bottom: .25rem; }"
        ),
        "table { border-collapse: collapse; width: 100%; margin: .5rem 0 1rem; }",
        (
            "th, td { text-align: left; padding: .35rem .6rem; "
            "border-bottom: 1px solid #e5e5e5; vertical-align: top; }"
        ),
        "th { font-weight: 600; background: #f6f6f6; }",
        "ul { margin: .3rem 0 1rem 1.2rem; }",
        "</style>",
        "</head>",
        "<body>",
        "<h1>usbscope report</h1>",
        "<ul>",
        f"<li><strong>Machine:</strong> {_esc(_machine(snapshot))}</li>",
        f"<li><strong>Host:</strong> {_esc(snapshot.host)}</li>",
        f"<li><strong>Read at:</strong> {_esc(_timestamp(snapshot.seen_at))}</li>",
        (
            f"<li><strong>Ports:</strong> {len(snapshot.ports)} total · "
            f"{len(snapshot.connected_ports)} connected · "
            f"{len(snapshot.emarked_cables)} e-marked cable(s)</li>"
        ),
        f"<li><strong>Devices:</strong> {len(snapshot.devices)}</li>",
        "</ul>",
    ]
    headers_for = {
        "Ports": PORT_HEADERS,
        "Devices": DEVICE_HEADERS,
        "Cables": CABLE_HEADERS,
        "Security findings": FINDING_HEADERS,
        "USB mass storage": STORAGE_HEADERS,
    }
    for title, rows, extra in _sections(snapshot, report, storage):
        lines.append(f"<h2>{_esc(title)}</h2>")
        headers = headers_for.get(title)
        if headers is not None:
            lines.extend(_html_table(headers, rows))
        for line in extra:
            if not line:
                continue
            if line.startswith("_") and line.endswith("_"):
                lines.append(f'<p class="muted">{_esc(line[1:-1])}</p>')
            elif line.startswith("- "):
                lines.append(f"<p>{_esc(line[2:])}</p>")
            else:
                lines.append(f"<p>{_esc(line)}</p>")
    lines.extend(("</body>", "</html>"))
    return "\n".join(lines) + "\n"
