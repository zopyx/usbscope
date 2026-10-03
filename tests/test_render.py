"""Tests for the Rich rendering (text assertions only, never ANSI codes)."""

from __future__ import annotations

from dataclasses import replace

from rich.console import Console

from usbscope.models import Snapshot, UsbDevice
from usbscope.render import build_view, render


def _console(width: int = 150) -> Console:
    return Console(
        width=width, record=True, force_terminal=False, color_system=None, highlight=False
    )


def _text(console: Console) -> str:
    return console.export_text()


def test_overview_wide(snapshot: Snapshot) -> None:
    console = _console(width=240)  # long reference strings must not wrap
    render(snapshot, console)
    out = _text(console)
    assert "usbscope" in out
    # derived from the snapshot, not from the machine running the suite
    assert f"{snapshot.model} · {snapshot.chip} · macOS {snapshot.os_version}" in out
    assert "6 total · 2 connected" in out
    assert "Ports & cables" in out
    assert "USB-C@3" in out
    assert "USB 1.1 Full-Speed · 12 Mbit/s" in out
    assert "Transports" in out and "Cable" in out
    assert "charge/accessory only" in out
    assert "no USB data transport" in out or "no USB data" in out
    assert "power in: USB-PD, Brick ID, TypeC" in out
    assert "🔐 Yubico YubiKey OTP+FIDO+CCID" in out
    assert "→ USB-C@3 via USB2" in out
    assert "Thunderbolt / USB4 receptacles" in out
    assert "Up to 40 Gb/s" in out
    assert "\x1b[" not in out  # no raw escape codes in the export


def test_overview_narrow_folds_columns(snapshot: Snapshot) -> None:
    console = _console(width=80)
    render(snapshot, console)
    out = _text(console)
    assert "Mode" in out
    assert "Transports" not in out  # folded into the notes column
    assert "modes:" in out  # short labels get a legend
    assert "cable:" in out
    assert "USB-C@3" in out


def test_default_implicitly_shows_hint_once_device_exists(snapshot: Snapshot) -> None:
    console = _console()
    render(snapshot, console)
    assert "No USB device is attached" not in _text(console)


def test_empty_snapshot_is_handled() -> None:
    from datetime import datetime

    empty = Snapshot(
        host="mac", os_version="27.0.1", seen_at=datetime(2026, 10, 2), model="Mac mini"
    )
    console = _console()
    render(empty, console)
    out = _text(console)
    assert "No USB device is attached" in out
    assert "Ports & cables" not in out
    assert "Devices (0)" in out
    assert "no USB buses reported" in out


def test_cables_view(snapshot: Snapshot) -> None:
    console = _console(width=200)  # the verbose cables table needs the room
    render(snapshot, console, view="cables", verbose=True)
    out = _text(console)
    assert "Cable & port controller" in out
    assert "CC authentication" in out
    assert "PD spec" in out
    assert "Power in" in out
    assert "USB mode" in out
    assert "Ports & cables" not in out


def test_verbose_shows_the_optional_controller_details(snapshot: Snapshot) -> None:
    """USB mode, pin assignment, power contract and LDCM only appear with -v."""
    console = _console(width=600)
    render(snapshot, console, verbose=True)
    out = _text(console)
    assert "USB mode: 2 (Device)" in out  # the port with the YubiKey
    assert "USB mode: 4" in out  # the charger-only port
    assert "pins: rx2=4, tx2=3" in out
    assert "power contract: mode 1, active 1, supported 1/3" in out
    assert "LDCM: Idle · No Error · Reference" in out


def test_optional_details_stay_out_of_the_default_view(snapshot: Snapshot) -> None:
    console = _console(width=600)
    render(snapshot, console)
    out = _text(console)
    assert "USB mode:" not in out
    assert "pins:" not in out
    assert "power contract:" not in out
    assert "LDCM:" not in out
    # the negotiated port contract is part of the port notes, the live charging
    # numbers are not
    assert "power in: USB-PD, Brick ID, TypeC (20 V · 5 A · 100 W)" in out
    assert "Charging & adapter" not in out
    assert "27.6 W in" not in out


def test_verbose_shows_the_live_charging_numbers(snapshot: Snapshot) -> None:
    console = _console(width=600)
    render(snapshot, console, view="cables", verbose=True)
    out = _text(console)
    assert "Charging & adapter" in out
    assert "system wide, not per port" in out
    assert "charging · 100 %" in out
    assert "70 W · 20 V · 3.5 A" in out  # what the adapter advertises
    assert "27.6 W · 19.5 V · 1.42 A" in out  # what actually comes in
    assert "16.1 W" in out  # system load
    assert "11.5 W · 13.0 V · 0.89 A" in out  # battery flow
    assert out.count("Charging & adapter") == 1


def test_the_summary_panel_gains_the_charging_rows_with_verbose(snapshot: Snapshot) -> None:
    console = _console(width=600)
    render(snapshot, console, verbose=True)
    out = _text(console)
    assert "Charging  charging · 100 %" in out
    assert "Power  27.6 W in · 11.5 W battery · 16.1 W system" in out


def test_devices_view_skips_port_table(snapshot: Snapshot) -> None:
    console = _console()
    render(snapshot, console, view="devices", verbose=True)
    out = _text(console)
    assert "Devices (1)" in out
    assert "Ports & cables" not in out
    assert "source=system_profiler" in out
    assert "location=0x01100000" in out


def test_warnings_are_rendered(snapshot: Snapshot) -> None:
    console = _console()
    render(replace(snapshot, warnings=("ioreg failed",)), console)
    out = _text(console)
    assert "notes" in out
    assert "ioreg failed" in out


def test_restricted_port_is_flagged_when_its_transport_is_active(snapshot: Snapshot) -> None:
    """macOS restriction is only shown for a transport that carries traffic."""
    port = next(item for item in snapshot.ports if item.description == "Port-USB-C@3")
    usb3 = port.transport("USB3")
    assert usb3 is not None and usb3.restricted is True

    # idle USB3 transport: the restriction is not worth showing
    idle = replace(
        snapshot,
        ports=tuple(replace(p, transports=(usb3,)) if p is port else p for p in snapshot.ports),
    )
    console = _console()
    render(idle, console)
    assert "restricted by macOS" not in _text(console)

    # same transport, now active
    active = replace(
        snapshot,
        ports=tuple(
            replace(p, transports=(replace(usb3, active=True, speed_mbps=5000),))
            if p is port
            else p
            for p in snapshot.ports
        ),
    )
    console = _console()
    render(active, console)
    assert "restricted by macOS" in _text(console)


def test_watch_refresh_counter_is_shown(snapshot: Snapshot) -> None:
    console = _console()
    render(snapshot, console, refresh=7)
    assert "refresh 7" in _text(console)


def test_build_view_returns_a_renderable(snapshot: Snapshot) -> None:
    """Live mode renders build_view() directly, so it must be a renderable, not prints."""
    console = _console()
    view = build_view(snapshot, console, view="ports", refresh=3)
    assert view is not None  # renderable object, nothing printed yet
    assert console.export_text() == ""

    console.print(view)
    out = _text(console)
    assert "Ports & cables" in out
    assert "refresh 3" in out


def test_build_view_respects_console_width(snapshot: Snapshot) -> None:
    narrow = _console(width=80)
    narrow.print(build_view(snapshot, narrow))
    assert "Transports" not in _text(narrow)

    wide = _console(width=150)
    wide.print(build_view(snapshot, wide))
    assert "Transports" in _text(wide)


def test_unknown_device_gets_default_icon(snapshot: Snapshot) -> None:
    device = UsbDevice(name="Some Gadget", vendor="Acme", vendor_id=1, product_id=2)
    console = _console()
    render(replace(snapshot, buses=()), console, view="devices")
    assert "no USB buses reported" in _text(console)
    console = _console()
    render(
        replace(
            snapshot,
            buses=(replace(snapshot.buses[0], devices=(device,)),),
        ),
        console,
        view="devices",
    )
    assert "🔹 Acme Some Gadget" in _text(console)
