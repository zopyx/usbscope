"""Tests for the AppKit layer.

They need PyObjC and a window server connection, so they are skipped where the
``macapp`` extra is missing. No window is ever shown: the delegate is driven
programmatically and the UI is captured offscreen instead.
"""

from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("AppKit", reason="requires the macapp extra (PyObjC)")

from AppKit import NSApplication, NSApplicationActivationPolicyRegular

from usbscope.macapp.app import AppDelegate, render_snapshot
from usbscope.macapp.viewmodel import VIEWS
from usbscope.models import Snapshot


@pytest.fixture
def delegate(snapshot: Snapshot) -> AppDelegate:
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    instance = AppDelegate.alloc().init()
    app.setDelegate_(instance)
    instance._build_window(show=False)
    instance.state.snapshot = snapshot
    instance.state.reads = 1
    instance.reload_table()
    return instance


def test_window_builds_with_toolbar(delegate: AppDelegate) -> None:
    assert delegate.window is not None
    assert delegate.window.title() == "usbscope — MacBook Pro · Apple M3 Pro · macOS 27.0.1"
    titles = [
        str(getattr(view, "title", lambda: "")())
        for view in delegate.window.contentView().subviews()
    ]
    assert "Refresh  ⌘R" in titles
    assert "Auto-refresh" in titles
    assert delegate.segments.segmentCount() == len(VIEWS)
    assert delegate.interval_popup.numberOfItems() == 4


def test_table_shows_the_ports_view(delegate: AppDelegate) -> None:
    assert delegate.numberOfRowsInTableView_(delegate.table) == 6
    assert [column.identifier() for column in delegate.table.tableColumns()] == [
        "port",
        "type",
        "state",
        "mode",
        "transports",
        "cable",
        "notes",
    ]
    cell = delegate.tableView_viewForTableColumn_row_(
        delegate.table, delegate.table.tableColumns()[0], 0
    )
    assert cell is not None
    assert cell.textField().stringValue() == "HDMI@1"


def test_switching_the_segmented_control_rebuilds_the_table(delegate: AppDelegate) -> None:
    delegate.segments.setSelectedSegment_(VIEWS.index("devices"))
    delegate.viewChanged_(delegate.segments)
    assert delegate.state.view == "devices"
    assert [column.identifier() for column in delegate.table.tableColumns()][:2] == [
        "name",
        "vendor",
    ]
    assert delegate.numberOfRowsInTableView_(delegate.table) == 1

    delegate.segments.setSelectedSegment_(VIEWS.index("thunderbolt"))
    delegate.viewChanged_(delegate.segments)
    assert delegate.numberOfRowsInTableView_(delegate.table) == 3


def test_auto_refresh_toggle_and_interval(delegate: AppDelegate) -> None:
    # building the window does not start the timer; the action does
    assert delegate.timer is None
    delegate.toggleAutoRefresh_(delegate.auto_toggle)  # switch is on by default
    assert delegate.state.interval == 2.0
    assert delegate.timer is not None

    delegate.auto_toggle.setState_(0)
    delegate.toggleAutoRefresh_(delegate.auto_toggle)
    assert delegate.state.interval is None
    assert delegate.timer is None
    assert "auto-refresh off" in delegate.status_label.stringValue()

    delegate.interval_popup.selectItemAtIndex_(2)  # 5 s
    delegate.auto_toggle.setState_(1)
    delegate.toggleAutoRefresh_(delegate.auto_toggle)
    assert delegate.state.interval == 5.0
    assert delegate.timer is not None


def test_refresh_increments_the_read_counter(
    delegate: AppDelegate, monkeypatch: pytest.MonkeyPatch
) -> None:
    reads_before = delegate.state.reads
    delegate.refresh_(None)
    assert delegate.state.reads == reads_before + 1
    assert "read #" in delegate.status_label.stringValue()


def test_refresh_failure_is_shown_instead_of_crashing(
    delegate: AppDelegate, monkeypatch: pytest.MonkeyPatch
) -> None:
    def boom() -> Snapshot:
        raise RuntimeError("system_profiler exploded")

    monkeypatch.setattr("usbscope.macapp.app.collect", boom)
    delegate.refresh_(None)
    assert "refresh failed" in delegate.status_label.stringValue()
    assert "system_profiler exploded" in delegate.status_label.stringValue()


@pytest.mark.parametrize("view", VIEWS)
def test_snapshot_render_produces_an_image(snapshot: Snapshot, view: str, tmp_path: Path) -> None:
    """The offscreen render is the UI test: it draws the real view hierarchy."""
    target = tmp_path / f"{view}.png"
    render_snapshot(target, view=view, snapshot=snapshot)
    assert target.exists()
    header = target.read_bytes()[:8]
    assert header == b"\x89PNG\r\n\x1a\n"
    assert target.stat().st_size > 10_000  # a real window, not an empty canvas


def test_snapshot_render_of_empty_machine(tmp_path: Path) -> None:
    from datetime import datetime

    empty = Snapshot(
        host="mac", os_version="27.0.1", seen_at=datetime(2026, 10, 2), model="Mac mini"
    )
    target = tmp_path / "empty.png"
    render_snapshot(target, snapshot=empty)
    assert target.exists()
