"""Tests for the AppKit layer.

They need PyObjC and a window server connection, so they are skipped where the
``macapp`` extra is missing. No window is ever shown: the delegate is driven
programmatically and the UI is captured offscreen instead.
"""

from __future__ import annotations

import csv
import json
from collections.abc import Iterator
from dataclasses import replace
from datetime import datetime
from pathlib import Path

import pytest

pytest.importorskip("AppKit", reason="requires the macapp extra (PyObjC)")

from AppKit import (
    NSApplication,
    NSApplicationActivationPolicyRegular,
    NSPasteboard,
    NSPasteboardTypeString,
    NSSortDescriptor,
    NSTextAlignmentRight,
)
from Foundation import NSIndexSet, NSMakeRect

from usbscope.macapp import preferences as prefs
from usbscope.macapp.app import AppDelegate, render_snapshot
from usbscope.macapp.viewmodel import VIEWS, device_key
from usbscope.models import Bus, Snapshot, UsbDevice


@pytest.fixture
def delegate(snapshot: Snapshot) -> AppDelegate:
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    instance = AppDelegate.alloc().init()
    instance.use_preferences = False  # the tests never touch the real defaults
    app.setDelegate_(instance)
    instance._build_menu()
    instance._build_window(show=False)
    instance.state.snapshot = snapshot
    instance.state.reads = 1
    instance.reload_table()
    return instance


@pytest.fixture
def clipboard() -> Iterator[None]:
    """Keep the developer's clipboard intact around a test that writes to it."""
    board = NSPasteboard.generalPasteboard()
    saved = board.stringForType_(NSPasteboardTypeString)
    try:
        yield
    finally:
        board.clearContents()
        if saved:
            board.setString_forType_(saved, NSPasteboardTypeString)


def _pasteboard_text() -> str:
    return str(NSPasteboard.generalPasteboard().stringForType_(NSPasteboardTypeString) or "")


def _select(delegate: AppDelegate, row: int) -> None:
    delegate.table.selectRowIndexes_byExtendingSelection_(NSIndexSet.indexSetWithIndex_(row), False)


def _submenu(title: str) -> object:
    """The app menu's submenu with the given title (PyObjC objects are untyped)."""
    main_menu = NSApplication.sharedApplication().mainMenu()
    return next(item.submenu() for item in main_menu.itemArray() if item.submenu().title() == title)


class _Store:
    """In-memory stand-in for ``NSUserDefaults``."""

    def __init__(self) -> None:
        self.values: dict[str, object] = {}

    def objectForKey_(self, key: str) -> object:
        return self.values.get(key)

    def setObject_forKey_(self, value: object, key: str) -> None:
        self.values[key] = value


def test_window_has_a_native_toolbar_with_all_controls(delegate: AppDelegate) -> None:
    assert delegate.window is not None
    assert delegate.window.title() == "usbscope — MacBook Pro · Apple M3 Pro · macOS 27.0.1"

    toolbar = delegate.window.toolbar()
    assert toolbar is not None
    identifiers = set(delegate.toolbarDefaultItemIdentifiers_(toolbar))
    assert {"usbscope.item.views", "usbscope.item.search", "usbscope.item.refresh"} <= identifiers
    assert (
        delegate.toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar_(
            toolbar, "usbscope.item.search", True
        )
        is not None
    )
    assert (
        delegate.toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar_(toolbar, "nope", True)
        is None
    )

    assert delegate.segments.segmentCount() == len(VIEWS)
    assert delegate.search_field.placeholderString() == "Filter"
    assert delegate.interval_popup.numberOfItems() == 4
    assert delegate.auto_toggle.title() == "Auto-refresh"
    assert delegate.refresh_button.title() == "Refresh  ⌘R"


def test_the_menus_offer_the_expected_actions(delegate: AppDelegate) -> None:
    main_menu = NSApplication.sharedApplication().mainMenu()
    titles = [
        item.submenu().title()
        for item in main_menu.itemArray()
        if item.submenu() and item.submenu().title()
    ]
    assert titles[:3] == ["Edit", "View", "File"]
    assert "Window" in titles
    help_entries = [
        entry.title()
        for item in main_menu.itemArray()
        if item.submenu() and item.submenu().title() == "Help"
        for entry in item.submenu().itemArray()
        if entry.title()
    ]
    assert help_entries == ["usbscope Documentation"]

    entries = [entry.title() for entry in _submenu("View").itemArray() if entry.title()]
    assert entries[:4] == ["Ports", "Cables", "Devices", "Thunderbolt"]
    assert "Refresh" in entries and "Auto-refresh" in entries
    assert [entry.tag() for entry in _submenu("View").itemArray()][:4] == [0, 1, 2, 3]

    edit_entries = [entry.title() for entry in _submenu("Edit").itemArray() if entry.title()]
    assert {"Copy Row", "Copy Table", "Copy as JSON", "Copy Details", "Find"} <= set(edit_entries)
    file_entries = [entry.title() for entry in _submenu("File").itemArray() if entry.title()]
    assert file_entries == ["Export JSON…", "Export CSV…"]


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


def test_columns_declare_a_sort_descriptor(delegate: AppDelegate) -> None:
    for column in delegate.table.tableColumns():
        prototype = column.sortDescriptorPrototype()
        assert prototype is not None
        assert prototype.key() == column.identifier()


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


def test_view_menu_selects_every_view(delegate: AppDelegate) -> None:
    for entry in _submenu("View").itemArray():
        if entry.title() in {"Ports", "Cables", "Devices", "Thunderbolt"}:
            delegate.selectView_(entry)
            assert delegate.state.view == entry.title().lower()
            assert delegate.segments.selectedSegment() == VIEWS.index(delegate.state.view)


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

    # the View menu entry flips the same switch
    delegate.toggleAutoRefreshMenu_(None)
    assert delegate.state.interval is None
    assert delegate.auto_toggle.state() == 0


def test_refresh_increments_the_read_counter(delegate: AppDelegate) -> None:
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


def test_refresh_highlights_a_new_device_then_clears_it(
    delegate: AppDelegate, snapshot: Snapshot, monkeypatch: pytest.MonkeyPatch
) -> None:
    stick = UsbDevice(name="Portable SSD", vendor="Samsung", vendor_id=0x04E8, product_id=0x61F5)
    plugged = replace(snapshot, buses=(*snapshot.buses, Bus(name="Extra", devices=(stick,))))
    monkeypatch.setattr("usbscope.macapp.app.collect", lambda: plugged)

    delegate.segments.setSelectedSegment_(VIEWS.index("devices"))
    delegate.viewChanged_(delegate.segments)
    delegate.refresh_(None)
    assert delegate.state.changes.count >= 1
    assert "changed:" in delegate.status_label.stringValue()

    row = delegate.model.row_keys.index(device_key(stick))
    assert delegate.model.highlight(row) is not None
    cell = delegate.tableView_viewForTableColumn_row_(
        delegate.table, delegate.table.tableColumns()[0], row
    )
    assert cell.layer().backgroundColor() is not None

    assert delegate.fade_timer is not None
    delegate.clearHighlights_(None)
    assert delegate.state.changes.is_empty
    assert all(highlight is None for highlight in delegate.model.row_highlights)
    assert "changed:" not in delegate.status_label.stringValue()


def test_search_filters_live_and_clears_again(delegate: AppDelegate) -> None:
    delegate.segments.setSelectedSegment_(VIEWS.index("devices"))
    delegate.viewChanged_(delegate.segments)
    assert delegate.numberOfRowsInTableView_(delegate.table) == 1

    delegate.search_field.setStringValue_("samsung")
    delegate.searchChanged_(delegate.search_field)
    assert delegate.state.filter_query == "samsung"
    assert delegate.numberOfRowsInTableView_(delegate.table) == 0
    assert delegate.empty_label.stringValue()  # the empty state explains itself
    assert "filter: 'samsung'" in delegate.status_label.stringValue()

    delegate.search_field.setStringValue_("")
    delegate.searchChanged_(delegate.search_field)
    assert delegate.numberOfRowsInTableView_(delegate.table) == 1


def test_search_keeps_the_filter_across_view_switches(delegate: AppDelegate) -> None:
    delegate.search_field.setStringValue_("yubikey")
    delegate.searchChanged_(delegate.search_field)
    delegate.segments.setSelectedSegment_(VIEWS.index("thunderbolt"))
    delegate.viewChanged_(delegate.segments)
    assert delegate.numberOfRowsInTableView_(delegate.table) == 0  # no receptacle says YubiKey


def test_clicking_a_header_sorts_and_clicking_again_reverses(delegate: AppDelegate) -> None:
    table = delegate.table
    table.setSortDescriptors_([NSSortDescriptor.sortDescriptorWithKey_ascending_("mode", True)])
    delegate.tableView_sortDescriptorsDidChange_(table, None)
    assert delegate.state.sort_column == 3
    assert delegate.state.sort_reverse is False
    ranks = [float(row[3].sort_value) for row in delegate.model.rows]
    assert ranks == sorted(ranks)

    table.setSortDescriptors_([NSSortDescriptor.sortDescriptorWithKey_ascending_("mode", False)])
    delegate.tableView_sortDescriptorsDidChange_(table, None)
    assert delegate.state.sort_reverse is True
    reversed_ranks = [float(row[3].sort_value) for row in delegate.model.rows]
    assert reversed_ranks == sorted(reversed_ranks, reverse=True)


def test_remembered_sort_state_is_applied(delegate: AppDelegate) -> None:
    delegate.state.sort_column = 3
    delegate.state.sort_reverse = True
    delegate.reload_table()
    descriptor = delegate.table.sortDescriptors()[0]
    assert descriptor.key() == "mode"
    assert descriptor.ascending() is False
    ranks = [float(row[3].sort_value) for row in delegate.model.rows]
    assert ranks == sorted(ranks, reverse=True)


def test_copy_row_table_and_json(delegate: AppDelegate, clipboard: None) -> None:
    delegate.segments.setSelectedSegment_(VIEWS.index("ports"))
    delegate.viewChanged_(delegate.segments)
    _select(delegate, 0)
    delegate.copyRow_(None)
    assert _pasteboard_text().startswith("HDMI@1\t")

    delegate.copyTable_(None)
    text = _pasteboard_text()
    assert text.splitlines()[0].split("\t")[0] == "Port"
    assert len(text.splitlines()) == delegate.model.row_count + 1

    delegate.copyJSON_(None)
    payload = json.loads(_pasteboard_text())
    assert payload["schema_version"] == 1

    delegate.copyDetails_(None)
    assert "Port: HDMI@1" in _pasteboard_text()

    delegate.copyCell_(None)  # nothing clicked: no crash, clipboard untouched
    assert "Port: HDMI@1" in _pasteboard_text()


def test_export_writes_json_and_csv(
    delegate: AppDelegate, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    json_path = tmp_path / "out.json"
    monkeypatch.setattr(AppDelegate, "_ask_for_save_path", lambda self, name: str(json_path))
    delegate.exportJSON_(None)
    assert json.loads(json_path.read_text())["schema_version"] == 1

    csv_path = tmp_path / "out.csv"
    monkeypatch.setattr(AppDelegate, "_ask_for_save_path", lambda self, name: str(csv_path))
    delegate.exportCSV_(None)
    rows = list(csv.reader(csv_path.read_text().splitlines()))
    assert rows[0][0] == "Port"
    assert len(rows) == delegate.model.row_count + 1


def test_export_is_cancelled_cleanly(
    delegate: AppDelegate, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(AppDelegate, "_ask_for_save_path", lambda self, name: None)
    delegate.exportJSON_(None)  # nothing written, no exception
    delegate.exportCSV_(None)


def test_detail_popover_shows_every_field(delegate: AppDelegate) -> None:
    delegate._show_popover(0)
    assert delegate.popover is not None
    labels = [
        view.stringValue()
        for view in delegate.popover.contentViewController().view().subviews()
        if hasattr(view, "stringValue")
    ]
    assert "Ports detail" in labels
    assert "Port" in labels
    assert "HDMI@1" in labels
    delegate.popover.close()


def test_double_click_without_a_selection_does_not_open_a_popover(delegate: AppDelegate) -> None:
    delegate.rowDoubleClicked_(delegate.table)  # clickedRow() is -1 outside a real click
    assert delegate.popover is None


def test_saving_records_what_the_user_chose(
    delegate: AppDelegate, monkeypatch: pytest.MonkeyPatch
) -> None:
    captured: list[prefs.Preferences] = []
    monkeypatch.setattr(
        prefs, "save", lambda preferences, defaults=None: captured.append(preferences)
    )
    delegate.use_preferences = True
    delegate.state.view = "cables"
    delegate.state.interval = 5.0
    delegate.state.sort_column = 1
    delegate.state.sort_reverse = True
    delegate.window.setFrame_display_(NSMakeRect(0.0, 0.0, 1000.0, 600.0), False)
    delegate._rebuild_columns(delegate.model)
    delegate._save_preferences()

    saved = captured[0].sanitized()
    assert saved.view == "cables"
    assert saved.interval == 5.0
    assert saved.sort_column == 1
    assert saved.sort_reverse is True
    assert saved.window_frame == (0.0, 0.0, 1000.0, 600.0)
    assert saved.column_widths["port"] > 0


def test_loading_restores_view_interval_and_sort(
    delegate: AppDelegate, monkeypatch: pytest.MonkeyPatch
) -> None:
    stored = prefs.Preferences(view="devices", interval=10.0, sort_column=0, sort_reverse=True)
    monkeypatch.setattr(prefs, "load", lambda defaults=None: stored)
    delegate.use_preferences = True
    delegate._load_preferences()
    assert delegate.state.view == "devices"
    assert delegate.state.interval == 10.0
    assert delegate.state.sort_column == 0
    assert delegate.state.sort_reverse is True


def test_store_roundtrip_through_the_fake_defaults(delegate: AppDelegate) -> None:
    store = _Store()
    delegate.use_preferences = True
    delegate.state.view = "thunderbolt"
    delegate.state.preferences = prefs.Preferences(view="thunderbolt", interval=1.0)
    prefs.save(delegate.state.preferences, store)
    restored = prefs.load(store)
    assert restored.view == "thunderbolt"
    assert restored.interval == 1.0


def test_snapshot_mode_never_reads_or_writes_preferences(
    snapshot: Snapshot, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[str] = []

    def record_load(defaults: object = None) -> prefs.Preferences:
        calls.append("load")
        return prefs.Preferences()

    def record_save(preferences: object, defaults: object = None) -> None:
        calls.append("save")

    monkeypatch.setattr(prefs, "load", record_load)
    monkeypatch.setattr(prefs, "save", record_save)

    app = NSApplication.sharedApplication()
    instance = AppDelegate.alloc().init()
    app.setDelegate_(instance)
    instance._build_window(show=False, snapshot_mode=True)
    instance.state.snapshot = snapshot
    instance.reload_table()
    instance._save_preferences()

    assert instance.use_preferences is False
    assert calls == []
    assert instance.window.toolbar() is None  # the capture draws plain labels instead


def test_refresh_keeps_the_selection_and_scroll_position(delegate: AppDelegate) -> None:
    table = delegate.table
    _select(delegate, 4)
    assert table.selectedRow() == 4
    key = delegate.model.row_keys[4]

    delegate.reload_table()  # what the auto-refresh does
    assert delegate.model.row_keys[table.selectedRow()] == key

    # the same after a sort reorders the rows: the key, not the index, is kept
    table.setSortDescriptors_([NSSortDescriptor.sortDescriptorWithKey_ascending_("port", False)])
    delegate.tableView_sortDescriptorsDidChange_(table, None)
    assert delegate.model.row_keys[table.selectedRow()] == key

    # and a selection that is gone (filtered out) simply leaves nothing selected
    delegate.search_field.setStringValue_("nothing matches this")
    delegate.searchChanged_(delegate.search_field)
    assert table.selectedRow() == -1


def test_controller_can_be_built_as_the_app_would(delegate: AppDelegate) -> None:
    """The delegate wires the status item; the controller itself is faked here so a
    test run never touches the developer's real menu bar or notification centre."""
    created: list[dict[str, object]] = []

    class FakeController:
        def __init__(
            self, *, on_refresh: object, on_select_view: object, on_show_window: object
        ) -> None:
            created.append(
                {"refresh": on_refresh, "select": on_select_view, "show": on_show_window}
            )
            self.updates: list[tuple[object, object]] = []
            self.views: list[str] = []
            self.notifications = True

        def set_notifications_enabled(self, enabled: bool) -> None:
            self.notifications = enabled

        def set_view(self, view: str) -> None:
            self.views.append(view)

        def update(self, snapshot: object, *, changes: object = None) -> None:
            self.updates.append((snapshot, changes))

        @property
        def notifications_enabled(self) -> bool:
            return self.notifications

    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr("usbscope.macapp.app.MenuBarController", FakeController)
    try:
        delegate._install_menubar()
        assert delegate.menubar is not None
        assert set(created[0]) == {"refresh", "select", "show"}

        # selecting a view from the status item follows the app state
        delegate._select_view("cables")
        assert delegate.state.view == "cables"
        assert delegate.menubar.views[-1] == "cables"
        assert delegate.segments.selectedSegment() == VIEWS.index("cables")

        # a refresh announces its changes exactly once, a re-render announces none
        delegate.reload_table()
        assert delegate.menubar.updates[-1] == (delegate.state.snapshot, None)
        delegate.refresh_(None)
        snapshot, changes = delegate.menubar.updates[-1]
        assert snapshot is delegate.state.snapshot
        assert changes is delegate.state.changes

        # the notification switch is persisted with the rest
        delegate.menubar.notifications = False
        delegate.use_preferences = True
        captured: list[object] = []
        monkeypatch.setattr(
            prefs, "save", lambda preferences, defaults=None: captured.append(preferences)
        )
        delegate._save_preferences()
        assert captured[0].notifications is False
    finally:
        monkeypatch.undo()


def test_numeric_columns_are_right_aligned(delegate: AppDelegate) -> None:
    delegate.segments.setSelectedSegment_(VIEWS.index("cables"))
    delegate.viewChanged_(delegate.segments)
    index = next(
        position for position, column in enumerate(delegate.model.columns) if column.key == "spec"
    )
    cell = delegate.tableView_viewForTableColumn_row_(
        delegate.table, delegate.table.tableColumns()[index], 1
    )
    assert cell.textField().alignment() == NSTextAlignmentRight


def test_row_tooltips_come_from_the_detail_pairs(delegate: AppDelegate) -> None:
    cell = delegate.tableView_viewForTableColumn_row_(
        delegate.table, delegate.table.tableColumns()[0], 0
    )
    tooltip = str(cell.toolTip())
    assert "Port: HDMI@1" in tooltip
    assert "Connected: no" in tooltip


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
    empty = Snapshot(
        host="mac", os_version="27.0.1", seen_at=datetime(2026, 10, 2), model="Mac mini"
    )
    target = tmp_path / "empty.png"
    render_snapshot(target, snapshot=empty)
    assert target.exists()
