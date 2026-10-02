"""Tests for the macOS app presentation model (no AppKit needed)."""

from __future__ import annotations

import pytest

from usbscope.macapp.viewmodel import (
    VIEWS,
    Style,
    device_tooltip,
    header_text,
    status_text,
    summary_text,
    table_model,
)
from usbscope.models import Snapshot


def test_views_are_complete(snapshot: Snapshot) -> None:
    assert VIEWS == ("ports", "cables", "devices", "thunderbolt")
    for view in VIEWS:
        model = table_model(snapshot, view)
        assert model.columns, view
        assert model.empty_message, view
        for row in model.rows:
            assert len(row) == len(model.columns), view


def test_unknown_view_is_rejected(snapshot: Snapshot) -> None:
    with pytest.raises(ValueError, match="unknown view"):
        table_model(snapshot, "nope")


def test_ports_model_matches_the_capture(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "ports")
    assert model.row_count == 6
    headers = [column.title for column in model.columns]
    assert headers == ["Port", "Type", "State", "Mode", "Transports", "Cable", "Notes"]

    rows = {row[0].text: row for row in model.rows}
    connected = rows["USB-C@3"]
    assert connected[1].text == "USB-C"
    assert connected[2].text == "● connected"
    assert connected[2].style is Style.GREEN
    assert "USB 1.1 Full-Speed" in connected[3].text
    assert connected[3].style is Style.YELLOW  # a 1.x link is not a highlight
    assert "USB2 ●" in connected[4].text
    assert connected[5].text == "unknown"
    assert "1 device(s): YubiKey" in connected[6].text

    charger = rows["USB-C@1"]
    assert charger[3].text == "no USB data"
    assert charger[3].style is Style.YELLOW
    assert "power in: USB-PD" in charger[6].text
    assert "charger/accessory only" in charger[6].text

    free = rows["USB-C@2"]
    assert free[2].text == "○ free"
    assert free[3].text == "–"
    assert free[6].text == "–"


def test_cables_model_has_cable_columns(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "cables")
    headers = [column.title for column in model.columns]
    assert headers[0] == "Port"
    assert "CC authentication" in headers
    assert "PD spec" in headers
    rows = {row[0].text: row for row in model.rows}
    assert rows["USB-C@1"][4].text == "3"  # PD (SOP) specification revision
    assert rows["USB-C@2"][1].text == "–"  # nothing attached


def test_devices_model_flattens_the_tree(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "devices")
    assert model.row_count == 1
    row = model.rows[0]
    assert row[0].text == "YubiKey OTP+FIDO+CCID"
    assert row[1].text == "Yubico"
    assert row[2].text == "0x1050:0x0407"
    assert row[3].text == "USB 1.1 Full-Speed · 12 Mbit/s"
    assert row[4].text == "USB-C@3"
    assert row[5].text == "USB2"
    assert row[8].text == "no"


def test_thunderbolt_model(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "thunderbolt")
    assert model.row_count == 3
    assert all(row[2].text == "○ free" for row in model.rows)
    assert all(row[3].text == "Up to 40 Gb/s" for row in model.rows)


def test_headers_and_status(snapshot: Snapshot) -> None:
    assert header_text(snapshot) == "usbscope — MacBook Pro · Apple M3 Pro · macOS 27.0.1"
    summary = summary_text(snapshot)
    assert summary.startswith("6 ports · 2 connected · 1 device(s)")
    assert "3 USB4 receptacle(s)" in summary

    status = status_text(snapshot, interval=2.0, reads=3)
    assert "read #3" in status
    assert "auto-refresh 2s" in status
    assert status_text(snapshot, interval=None, reads=1).count("auto-refresh off") == 1


def test_warnings_surface_in_the_status_line(snapshot: Snapshot) -> None:
    from dataclasses import replace

    status = status_text(replace(snapshot, warnings=("ioreg failed",)), interval=5.0, reads=2)
    assert "1 warning(s): ioreg failed" in status


def test_empty_snapshot_uses_the_empty_messages() -> None:
    from datetime import datetime

    empty = Snapshot(host="mac", os_version="27.0.1", seen_at=datetime(2026, 10, 2))
    for view in VIEWS:
        model = table_model(empty, view)
        assert model.row_count == 0
        assert model.empty_message.endswith(".")


def test_device_tooltip_lists_the_facts(snapshot: Snapshot) -> None:
    tooltip = device_tooltip(snapshot.devices[0])
    assert "YubiKey OTP+FIDO+CCID" in tooltip
    assert "0x1050:0x0407" in tooltip
    assert "USB-C@3" in tooltip
    assert "Location ID: 0x01100000" in tooltip
