"""Tests for the macOS app presentation model (no AppKit needed)."""

from __future__ import annotations

import pytest

from usbscope.macapp.viewmodel import (
    ADDED,
    CHANGED,
    REMOVED,
    VIEWS,
    ChangeSet,
    Style,
    apply_changes,
    detail_pairs,
    device_key,
    device_tooltip,
    header_text,
    port_key,
    row_tooltip,
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


def test_every_row_has_a_key(snapshot: Snapshot) -> None:
    for view in VIEWS:
        model = table_model(snapshot, view)
        assert len(model.row_keys) == model.row_count, view
        assert len(set(model.row_keys)) == model.row_count, view
        assert all(key for key in model.row_keys), view


def test_apply_changes_colours_the_affected_rows(snapshot: Snapshot) -> None:
    devices = table_model(snapshot, "devices")
    added = apply_changes(devices, ChangeSet(added=snapshot.devices))
    assert added.row_highlights == (Style.GREEN,)
    assert added.highlight(0) is Style.GREEN

    removed = apply_changes(devices, ChangeSet(removed=snapshot.devices))
    assert removed.highlight(0) is Style.RED

    ports = table_model(snapshot, "ports")
    changed = apply_changes(ports, ChangeSet(changed_ports=(port_key(snapshot.ports[0]),)))
    assert changed.highlight(0) is Style.YELLOW
    assert changed.highlight(1) is None

    plain = apply_changes(ports, None)
    assert plain.row_highlights == ()
    assert plain.highlight(0) is None


def test_apply_changes_tags_match_the_constants(snapshot: Snapshot) -> None:
    assert (ADDED, REMOVED, CHANGED) == ("added", "removed", "changed")


def test_detail_pairs_cover_ports_cables_devices_and_thunderbolt(snapshot: Snapshot) -> None:
    port_key_name = port_key(snapshot.ports[0])
    port_pairs = dict(detail_pairs(snapshot, "ports", port_key_name))
    assert port_pairs["Port"] == snapshot.ports[0].name
    assert "Connected" in port_pairs

    cabled = next(port for port in snapshot.ports if port.cable.attached)
    cable_pairs = dict(detail_pairs(snapshot, "cables", port_key(cabled)))
    assert "CC authentication" in cable_pairs
    assert "PD specification" in cable_pairs

    device_pairs = dict(detail_pairs(snapshot, "devices", device_key(snapshot.devices[0])))
    assert device_pairs["VID:PID"] == "0x1050:0x0407"
    assert device_pairs["Restricted by macOS"] == "no"

    tb_key_text = table_model(snapshot, "thunderbolt").row_keys[0]
    tb_pairs = dict(detail_pairs(snapshot, "thunderbolt", tb_key_text))
    assert tb_pairs["Receptacle"]


def test_details_ignore_unknown_keys(snapshot: Snapshot) -> None:
    assert detail_pairs(snapshot, "ports", "port:USB-C@99") == ()
    assert row_tooltip(snapshot, "devices", "device:serial:nope") == ""


def test_row_tooltip_works_for_port_rows_too(snapshot: Snapshot) -> None:
    tooltip = row_tooltip(snapshot, "ports", port_key(snapshot.ports[1]))
    assert f"Port: {snapshot.ports[1].name}" in tooltip


def test_status_text_reports_changes_and_filter(snapshot: Snapshot) -> None:
    quiet = status_text(snapshot, interval=2.0, reads=4, changes=ChangeSet())
    assert "changed:" not in quiet

    noisy = status_text(snapshot, interval=2.0, reads=4, changes=ChangeSet(added=snapshot.devices))
    assert "changed: 1 added" in noisy

    filtered = status_text(snapshot, interval=None, reads=1, filter_query="yubikey")
    assert "filter: 'yubikey'" in filtered
