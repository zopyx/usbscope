"""Native macOS UI (AppKit) for usbscope.

A real Cocoa window, built from AppKit alone (``NSWindow``, ``NSToolbar``,
``NSTableView``, ``NSPopover``): four views behind a segmented control in an
unified toolbar, live search, sortable columns, row highlighting for devices that
appeared or disappeared, clipboard export, a detail popover and a refresh timer.

State is remembered in ``NSUserDefaults`` (view, cadence, sort, column widths,
window frame), so a restart looks like the last session.

``usbscope-app --snapshot out.png`` renders the window offscreen to a PNG and
exits, which makes the UI verifiable (and documentable) on a machine without the
Screen Recording permission that ``screencapture`` needs.
"""

from __future__ import annotations

import argparse
import sys
import traceback
from dataclasses import dataclass, field, replace
from pathlib import Path

import objc
from AppKit import (
    NSApp,
    NSApplication,
    NSApplicationActivationPolicyRegular,
    NSBackingStoreBuffered,
    NSBezelStyleRounded,
    NSBitmapImageFileTypePNG,
    NSButton,
    NSButtonTypeSwitch,
    NSColor,
    NSFont,
    NSFontWeightMedium,
    NSFontWeightSemibold,
    NSLineBreakByTruncatingTail,
    NSMenu,
    NSMenuItem,
    NSPasteboard,
    NSPasteboardTypeString,
    NSPopover,
    NSPopoverBehaviorTransient,
    NSPopUpButton,
    NSRectEdgeMaxX,
    NSSavePanel,
    NSScrollView,
    NSSearchField,
    NSSegmentedControl,
    NSSegmentStyleRounded,
    NSSegmentSwitchTrackingSelectOne,
    NSSortDescriptor,
    NSTableCellView,
    NSTableColumn,
    NSTableView,
    NSTextAlignmentRight,
    NSTextField,
    NSToolbar,
    NSToolbarFlexibleSpaceItemIdentifier,
    NSToolbarItem,
    NSToolbarSpaceItemIdentifier,
    NSView,
    NSViewController,
    NSViewHeightSizable,
    NSViewMaxYMargin,
    NSViewMinYMargin,
    NSViewWidthSizable,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
    NSWindowToolbarStyleUnifiedCompact,
    NSWorkspace,
)
from Foundation import NSURL, NSMakeRect, NSMutableIndexSet, NSObject, NSTimer

from .. import __version__
from ..models import Snapshot
from ..serialize import snapshot_to_json
from ..snapshot import collect
from . import preferences as prefs
from .changes import ChangeSet, diff_snapshots
from .menubar import MenuBarController
from .tableops import filter_model, sort_model, to_csv
from .viewmodel import (
    VIEWS,
    Align,
    Cell,
    Style,
    TableModel,
    apply_changes,
    detail_pairs,
    header_text,
    row_tooltip,
    status_text,
    summary_text,
    table_model,
)

WINDOW_WIDTH = 1440.0
WINDOW_HEIGHT = 700.0
MIN_WIDTH = 900.0
MIN_HEIGHT = 420.0
ROW_HEIGHT = 22.0
MARGIN = 16.0
TOOLBAR_HEIGHT = 26.0
STATUS_HEIGHT = 16.0
HIGHLIGHT_SECONDS = 1.6
DOCS_URL = "https://github.com/zopyx/usbscope#readme"

TOOLBAR_IDENTIFIER = "com.zopyx.usbscope.toolbar"
ITEM_VIEWS = "usbscope.item.views"
ITEM_SEARCH = "usbscope.item.search"
ITEM_COPY = "usbscope.item.copy"
ITEM_EXPORT = "usbscope.item.export"
ITEM_REFRESH = "usbscope.item.refresh"
ITEM_DETAILS = "usbscope.item.details"
ITEM_SPACER = "usbscope.item.spacer"
ITEM_TOGGLE = "usbscope.item.toggle"
ITEM_INTERVAL = "usbscope.item.interval"

_STYLE_COLORS: dict[Style, str] = {
    Style.DEFAULT: "labelColor",
    Style.DIM: "secondaryLabelColor",
    Style.BOLD: "labelColor",
    Style.GREEN: "systemGreenColor",
    Style.YELLOW: "systemOrangeColor",
    Style.RED: "systemRedColor",
    Style.CYAN: "systemTealColor",
    Style.MAGENTA: "systemPurpleColor",
}

_HIGHLIGHT_COLORS: dict[Style, str] = {
    Style.GREEN: "systemGreenColor",
    Style.RED: "systemRedColor",
    Style.YELLOW: "systemOrangeColor",
}

_BOLD_STYLES = {Style.BOLD}
_NUMERIC_KEYS = {"pd_spec", "receptacle", "spec", "number"}


def _color(style: Style) -> NSColor:
    """Map a semantic style onto a system colour (dark mode aware)."""
    return getattr(NSColor, _STYLE_COLORS[style])()


def _mono_font(size: float, *, bold: bool = False, digits: bool = False) -> NSFont:
    """Monospaced font; ``digits`` keeps numbers aligned inside proportional text."""
    weight = NSFontWeightSemibold if bold else 0.0
    if digits:
        font = NSFont.monospacedDigitSystemFontOfSize_weight_(size, NSFontWeightMedium)
    else:
        font = NSFont.monospacedSystemFontOfSize_weight_(size, weight)
    return font or NSFont.systemFontOfSize_(size)


def _label(
    text: str,
    frame: tuple[float, ...],
    *,
    size: float = 12.0,
    mono: bool = True,
    mask: int = 0,
) -> NSTextField:
    """A selectable label with an explicit frame (and optional autoresizing mask).

    Labels get their frame up front: a label created empty and filled later has no
    intrinsic width, so anything that sizes views by content (a stack view, a
    packed cell) would leave it invisible.
    """
    field = NSTextField.labelWithString_(text)
    field.setFrame_(frame)
    field.setFont_(_mono_font(size) if mono else NSFont.systemFontOfSize_(size))
    field.setLineBreakMode_(NSLineBreakByTruncatingTail)
    field.setSelectable_(True)
    # layer backed: a plain (non layer backed) label next to the layer backed
    # scroll view disappears from the offscreen `--snapshot` bitmap
    field.setWantsLayer_(True)
    if mask:
        field.setAutoresizingMask_(mask)
    return field


@dataclass
class AppState:
    """State of the running app."""

    view: str = VIEWS[0]
    interval: float | None = prefs.DEFAULT_INTERVAL
    reads: int = 0
    snapshot: Snapshot | None = None
    changes: ChangeSet = field(default_factory=ChangeSet)
    filter_query: str = ""
    sort_column: int | None = None
    sort_reverse: bool = False
    preferences: prefs.Preferences = field(default_factory=prefs.Preferences)
    notifications: bool = True


class AppDelegate(NSObject):
    """Window, toolbar, table data source, refresh timer and menu actions."""

    def init(self) -> AppDelegate:
        self = objc.super(AppDelegate, self).init()
        if self is None:  # pragma: no cover - Objective-C init contract
            raise RuntimeError("AppDelegate could not be initialised")
        self.state = AppState()
        self.model: TableModel | None = None
        self.timer: NSTimer | None = None
        self.fade_timer: NSTimer | None = None
        self.window: NSWindow | None = None
        self.segments: NSSegmentedControl | None = None
        self.search_field: NSSearchField | None = None
        self.copy_popup: NSPopUpButton | None = None
        self.export_popup: NSPopUpButton | None = None
        self.refresh_button: NSButton | None = None
        self.details_button: NSButton | None = None
        self.auto_toggle: NSButton | None = None
        self.interval_popup: NSPopUpButton | None = None
        self.toolbar: NSToolbar | None = None
        self.popover: NSPopover | None = None
        self.menubar: MenuBarController | None = None
        self._menubar_error: str | None = None
        self.snapshot_mode = False
        self.use_preferences = True
        self.syncing_sort = False
        return self

    # ------------------------------------------------------------------ setup
    def applicationDidFinishLaunching_(self, _notification: object) -> None:
        self._load_preferences()
        self._build_menu()
        self._build_window()
        self._install_menubar()
        self.refresh_(None)
        self._schedule_timer()
        NSApp.activate()

    def _install_menubar(self) -> None:
        """Add the menu bar extra (status item) with the app as its target."""
        try:
            controller = MenuBarController(
                on_refresh=lambda: self.refresh_(None),
                on_select_view=self._select_view,
                on_show_window=self._show_window,
            )
        except Exception as error:  # a missing status bar must not block the window
            self.menubar = None
            self._menubar_error = str(error)
            return
        controller.set_notifications_enabled(self.state.notifications)
        controller.set_view(self.state.view)
        self.menubar = controller
        self._menubar_error = None

    def _update_menubar(self, *, changes: ChangeSet | None = None) -> None:
        """Mirror the current state in the status item; announce device changes once."""
        if self.menubar is None or self.state.snapshot is None:
            return
        self.menubar.update(self.state.snapshot, changes=changes)

    def _sync_menubar_view(self) -> None:
        if self.menubar is not None:
            self.menubar.set_view(self.state.view)

    def _select_view(self, view: str) -> None:
        """Select ``view`` from anywhere (segmented control, menu, status item)."""
        if view not in VIEWS:
            return
        self.state.view = view
        if self.segments is not None:
            self.segments.setSelectedSegment_(VIEWS.index(view))
        self._sync_menubar_view()
        self.reload_table()

    def _show_window(self) -> None:
        """Bring the window back (the status item's ``Open usbscope``)."""
        if self.window is not None:
            self.window.makeKeyAndOrderFront_(None)
        NSApp.activate()

    def applicationShouldTerminateAfterLastWindowClosed_(self, _sender: object) -> bool:
        return True

    def applicationWillTerminate_(self, _notification: object) -> None:
        self._save_preferences()

    def quit_(self, _sender: object) -> None:
        NSApp.terminate_(None)

    def _load_preferences(self) -> None:
        if not self.use_preferences:
            return
        stored = prefs.load()
        self.state.preferences = stored
        self.state.view = stored.view
        self.state.interval = stored.interval
        self.state.sort_column = stored.sort_column
        self.state.sort_reverse = stored.sort_reverse
        self.state.notifications = stored.notifications

    def _save_preferences(self) -> None:
        if not self.use_preferences or self.window is None:
            return
        frame = self.window.frame()
        notifications = (
            self.menubar.notifications_enabled
            if self.menubar is not None
            else self.state.notifications
        )
        self.state.notifications = notifications
        self.state.preferences = replace(
            self.state.preferences,
            view=self.state.view,
            interval=self.state.interval,
            sort_column=self.state.sort_column,
            sort_reverse=self.state.sort_reverse,
            notifications=notifications,
            window_frame=(
                float(frame.origin.x),
                float(frame.origin.y),
                float(frame.size.width),
                float(frame.size.height),
            ),
            column_widths=self._current_column_widths(),
        )
        prefs.save(self.state.preferences)

    def _build_menu(self) -> None:
        """App, Edit, View, File and Help menus with the usual shortcuts."""
        main_menu = NSMenu.alloc().init()

        app_item = NSMenuItem.alloc().init()
        main_menu.addItem_(app_item)
        app_menu = NSMenu.alloc().init()
        about = app_menu.addItemWithTitle_action_keyEquivalent_(
            f"About usbscope {__version__}", "showAbout:", ""
        )
        about.setTarget_(self)
        app_menu.addItemWithTitle_action_keyEquivalent_("Hide usbscope", "hide:", "h")
        app_menu.addItemWithTitle_action_keyEquivalent_("Quit usbscope", "terminate:", "q")
        app_item.setSubmenu_(app_menu)

        edit_item = NSMenuItem.alloc().init()
        main_menu.addItem_(edit_item)
        edit_menu = NSMenu.alloc().init()
        edit_menu.setTitle_("Edit")
        for title, selector, key in (
            ("Copy Row", "copyRow:", "c"),
            ("Copy Table", "copyTable:", "C"),
            ("Copy as JSON", "copyJSON:", ""),
            ("Copy Details", "copyDetails:", "d"),
        ):
            entry = edit_menu.addItemWithTitle_action_keyEquivalent_(title, selector, key)
            entry.setTarget_(self)
        edit_menu.addItem_(NSMenuItem.separatorItem())
        find_item = edit_menu.addItemWithTitle_action_keyEquivalent_("Find", "focusSearch:", "f")
        find_item.setTarget_(self)
        edit_item.setSubmenu_(edit_menu)

        view_item = NSMenuItem.alloc().init()
        main_menu.addItem_(view_item)
        view_menu = NSMenu.alloc().init()
        view_menu.setTitle_("View")
        for index, view in enumerate(VIEWS):
            entry = view_menu.addItemWithTitle_action_keyEquivalent_(
                view.capitalize(), "selectView:", str(index + 1)
            )
            entry.setTag_(index)
            entry.setTarget_(self)
        view_menu.addItem_(NSMenuItem.separatorItem())
        refresh = view_menu.addItemWithTitle_action_keyEquivalent_("Refresh", "refresh:", "r")
        refresh.setTarget_(self)
        auto = view_menu.addItemWithTitle_action_keyEquivalent_(
            "Auto-refresh", "toggleAutoRefreshMenu:", ""
        )
        auto.setTarget_(self)
        view_item.setSubmenu_(view_menu)

        file_item = NSMenuItem.alloc().init()
        main_menu.addItem_(file_item)
        file_menu = NSMenu.alloc().init()
        file_menu.setTitle_("File")
        for title, selector, key in (
            ("Export JSON…", "exportJSON:", "s"),
            ("Export CSV…", "exportCSV:", "S"),
        ):
            entry = file_menu.addItemWithTitle_action_keyEquivalent_(title, selector, key)
            entry.setTarget_(self)
        file_item.setSubmenu_(file_menu)

        window_item = NSMenuItem.alloc().init()
        main_menu.addItem_(window_item)
        window_menu = NSMenu.alloc().init()
        window_menu.setTitle_("Window")
        window_menu.addItemWithTitle_action_keyEquivalent_("Minimize", "performMiniaturize:", "m")
        window_item.setSubmenu_(window_menu)
        NSApp.setWindowsMenu_(window_menu)

        help_item = NSMenuItem.alloc().init()
        main_menu.addItem_(help_item)
        help_menu = NSMenu.alloc().init()
        help_menu.setTitle_("Help")
        docs = help_menu.addItemWithTitle_action_keyEquivalent_(
            "usbscope Documentation", "showDocs:", ""
        )
        docs.setTarget_(self)
        help_item.setSubmenu_(help_menu)
        NSApp.setHelpMenu_(help_menu)

        NSApp.setMainMenu_(main_menu)

    def _build_window(self, *, show: bool = True, snapshot_mode: bool = False) -> None:
        rect = NSMakeRect(0.0, 0.0, WINDOW_WIDTH, WINDOW_HEIGHT)
        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            rect,
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskMiniaturizable
            | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered,
            False,
        )
        window.setTitle_(f"usbscope {__version__}")
        window.setMinSize_((MIN_WIDTH, MIN_HEIGHT))
        window.setDelegate_(self)
        window.center()

        self.snapshot_mode = snapshot_mode
        if snapshot_mode:
            self.use_preferences = False
        root = NSView.alloc().initWithFrame_(rect)
        # Layer backing: recommended for modern AppKit, and required for the
        # offscreen `--snapshot` render — without it the scroll view's layer tree
        # hides the plain sibling labels in the captured bitmap.
        root.setWantsLayer_(True)
        window.setContentView_(root)

        self._install_toolbar(window)

        width = root.bounds().size.width
        height = root.bounds().size.height
        # the toolbar lives in the frame, not in the content view: no extra offset
        top = height - MARGIN
        self.summary_label = _label(
            "",
            NSMakeRect(MARGIN, top - 17.0, width - 2.0 * MARGIN, 17.0),
            size=12.5,
            mono=False,
            mask=NSViewMinYMargin | NSViewWidthSizable,
        )
        root.addSubview_(self.summary_label)

        table_top = top - 17.0 - 10.0
        table_bottom = MARGIN + STATUS_HEIGHT + 14.0
        root.addSubview_(
            self._build_table(
                NSMakeRect(MARGIN, table_bottom, width - 2.0 * MARGIN, table_top - table_bottom)
            )
        )

        self.empty_label = _label(
            "",
            NSMakeRect(MARGIN + 12.0, table_bottom - 22.0, width - 2.0 * MARGIN - 24.0, 16.0),
            size=12.0,
            mono=False,
            mask=NSViewMinYMargin | NSViewWidthSizable,
        )
        self.empty_label.setTextColor_(NSColor.secondaryLabelColor())
        root.addSubview_(self.empty_label)

        self.status_label = _label(
            "",
            NSMakeRect(MARGIN, MARGIN, width - 2.0 * MARGIN, STATUS_HEIGHT),
            size=11.0,
            mask=NSViewMaxYMargin | NSViewWidthSizable,
        )
        self.status_label.setTextColor_(NSColor.secondaryLabelColor())
        root.addSubview_(self.status_label)

        self.window = window
        self._apply_stored_frame()
        if show:
            window.makeKeyAndOrderFront_(None)

    def _apply_stored_frame(self) -> None:
        """Apply the remembered window frame (when it is usable on this screen)."""
        frame = self.state.preferences.window_frame
        if not self.use_preferences or frame is None or self.window is None:
            return
        self.window.setFrame_display_(NSMakeRect(*frame), True)

    def _install_toolbar(self, window: NSWindow) -> None:
        """Put the controls into a real unified ``NSToolbar``.

        The controls must exist *before* ``setToolbar_``: AppKit asks the delegate
        for every default item while that call runs, and a delegate that cannot
        produce the item's view is silently skipped — which leaves an apparently
        empty toolbar above the table.
        """
        self.segments = self._make_segments()
        self.search_field = self._make_search_field()
        self.copy_popup = self._make_copy_popup()
        self.export_popup = self._make_export_popup()
        self.refresh_button = self._make_refresh_button()
        self.details_button = self._make_details_button()
        self.auto_toggle = self._make_auto_toggle()
        self.interval_popup = self._make_interval_popup()

        toolbar = NSToolbar.alloc().initWithIdentifier_(TOOLBAR_IDENTIFIER)
        toolbar.setDelegate_(self)
        toolbar.setAllowsUserCustomization_(False)
        toolbar.setAutosavesConfiguration_(False)
        window.setToolbarStyle_(NSWindowToolbarStyleUnifiedCompact)
        window.setToolbar_(toolbar)  # populates the items right here
        self.toolbar = toolbar

    def _make_segments(self) -> NSSegmentedControl:
        segments = NSSegmentedControl.alloc().initWithFrame_(
            NSMakeRect(0.0, 0.0, 404.0, TOOLBAR_HEIGHT)
        )
        segments.setSegmentCount_(len(VIEWS))
        for index, view in enumerate(VIEWS):
            segments.setLabel_forSegment_(view.capitalize(), index)
            segments.setWidth_forSegment_(97.0, index)
        segments.setSegmentStyle_(NSSegmentStyleRounded)
        segments.setTrackingMode_(NSSegmentSwitchTrackingSelectOne)
        segments.setSelectedSegment_(VIEWS.index(self.state.view))
        segments.setTarget_(self)
        segments.setAction_("viewChanged:")
        return segments

    def _make_search_field(self) -> NSSearchField:
        field = NSSearchField.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, 172.0, TOOLBAR_HEIGHT))
        field.setPlaceholderString_("Filter")
        field.setTarget_(self)
        field.setAction_("searchChanged:")
        field.setSendsSearchStringImmediately_(True)
        field.setDelegate_(self)
        field.setStringValue_(self.state.filter_query)
        return field

    def _make_refresh_button(self) -> NSButton:
        button = NSButton.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, 112.0, TOOLBAR_HEIGHT))
        button.setTitle_("Refresh  ⌘R")
        button.setBezelStyle_(NSBezelStyleRounded)
        button.setTarget_(self)
        button.setAction_("refresh:")
        button.setToolTip_("Read the USB tree again (⌘R)")
        return button

    def _make_copy_popup(self) -> NSPopUpButton:
        """Pull-down button that exposes the clipboard actions (they were menu-only)."""
        popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(
            NSMakeRect(0.0, 0.0, 116.0, TOOLBAR_HEIGHT), True
        )
        popup.addItemWithTitle_("Copy")
        popup.setToolTip_("Copy rows, table, details or the snapshot as JSON")
        self._add_popup_actions(
            popup,
            (
                ("Selected Rows", "copyRow:", "Copy the selected rows as TSV (⌘C)"),
                ("Whole Table", "copyTable:", "Copy the whole table as TSV (⇧⌘C)"),
                ("Details", "copyDetails:", "Copy every known field of the selection (⌘D)"),
                ("Snapshot as JSON", "copyJSON:", "Copy the raw snapshot as JSON"),
            ),
        )
        return popup

    def _make_export_popup(self) -> NSPopUpButton:
        """Pull-down button for ``File ▸ Export`` (was menu-only)."""
        popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(
            NSMakeRect(0.0, 0.0, 104.0, TOOLBAR_HEIGHT), True
        )
        popup.addItemWithTitle_("Export")
        popup.setToolTip_("Write the current view or the snapshot to a file")
        self._add_popup_actions(
            popup,
            (
                ("Current View as CSV…", "exportCSV:", "Write the shown table as CSV (⇧⌘S)"),
                ("Snapshot as JSON…", "exportJSON:", "Write the whole snapshot as JSON (⌘S)"),
            ),
        )
        return popup

    def _add_popup_actions(
        self, popup: NSPopUpButton, entries: tuple[tuple[str, str, str], ...]
    ) -> None:
        """Give every pull-down entry its own target/action (item 0 is the title).

        Each entry calls the same selector the menu uses, so both routes stay in
        sync by construction.
        """
        for title, selector, tooltip in entries:
            popup.addItemWithTitle_(title)
            item = popup.lastItem()
            item.setTarget_(self)
            item.setAction_(selector)
            item.setToolTip_(tooltip)

    def _make_details_button(self) -> NSButton:
        button = NSButton.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, 84.0, TOOLBAR_HEIGHT))
        button.setTitle_("Details")
        button.setBezelStyle_(NSBezelStyleRounded)
        button.setTarget_(self)
        button.setAction_("showDetails:")
        button.setToolTip_("Show every field of the selected row")
        return button

    def _make_auto_toggle(self) -> NSButton:
        toggle = NSButton.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, 114.0, TOOLBAR_HEIGHT))
        toggle.setButtonType_(NSButtonTypeSwitch)
        toggle.setTitle_("Auto-refresh")
        toggle.setState_(1 if self.state.interval else 0)
        toggle.setTarget_(self)
        toggle.setAction_("toggleAutoRefresh:")
        toggle.setToolTip_("Refresh on a timer while the table is visible")
        return toggle

    def _make_interval_popup(self) -> NSPopUpButton:
        popup = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, 78.0, TOOLBAR_HEIGHT))
        popup.addItemsWithTitles_([f"{value:g} s" for value in prefs.INTERVALS])
        popup.selectItemAtIndex_(
            prefs.INTERVALS.index(self.state.interval)
            if self.state.interval in prefs.INTERVALS
            else 1
        )
        popup.setTarget_(self)
        popup.setAction_("intervalChanged:")
        popup.setToolTip_("Auto-refresh interval")
        return popup

    def _make_toolbar_item(
        self, identifier: str, view: NSView, label: str, width: float
    ) -> NSToolbarItem:
        item = NSToolbarItem.alloc().initWithItemIdentifier_(identifier)
        item.setLabel_(label)
        item.setPaletteLabel_(label)
        item.setToolTip_(label)
        item.setView_(view)
        item.setMinSize_((width, TOOLBAR_HEIGHT))
        item.setMaxSize_((width, TOOLBAR_HEIGHT))
        return item

    # NSToolbarDelegate
    def toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar_(
        self, _toolbar: NSToolbar, identifier: str, _flag: bool
    ) -> NSToolbarItem | None:
        if identifier == ITEM_VIEWS and self.segments is not None:
            return self._make_toolbar_item(identifier, self.segments, "Views", 404.0)
        if identifier == ITEM_SEARCH and self.search_field is not None:
            return self._make_toolbar_item(identifier, self.search_field, "Filter", 172.0)
        if identifier == ITEM_COPY and self.copy_popup is not None:
            return self._make_toolbar_item(identifier, self.copy_popup, "Copy", 116.0)
        if identifier == ITEM_EXPORT and self.export_popup is not None:
            return self._make_toolbar_item(identifier, self.export_popup, "Export", 108.0)
        if identifier == ITEM_REFRESH and self.refresh_button is not None:
            return self._make_toolbar_item(identifier, self.refresh_button, "Refresh", 116.0)
        if identifier == ITEM_DETAILS and self.details_button is not None:
            return self._make_toolbar_item(identifier, self.details_button, "Details", 88.0)
        if identifier == ITEM_TOGGLE and self.auto_toggle is not None:
            return self._make_toolbar_item(identifier, self.auto_toggle, "Auto-refresh", 118.0)
        if identifier == ITEM_INTERVAL and self.interval_popup is not None:
            return self._make_toolbar_item(identifier, self.interval_popup, "Interval", 82.0)
        if identifier == ITEM_SPACER:
            item = NSToolbarItem.alloc().initWithItemIdentifier_(NSToolbarSpaceItemIdentifier)
            return item
        return None

    def toolbarAllowedItemIdentifiers_(self, _toolbar: NSToolbar) -> list[str]:
        return [
            ITEM_VIEWS,
            ITEM_SEARCH,
            ITEM_COPY,
            ITEM_EXPORT,
            ITEM_REFRESH,
            ITEM_DETAILS,
            ITEM_TOGGLE,
            ITEM_INTERVAL,
            NSToolbarFlexibleSpaceItemIdentifier,
            ITEM_SPACER,
        ]

    def toolbarDefaultItemIdentifiers_(self, _toolbar: NSToolbar) -> list[str]:
        return [
            ITEM_VIEWS,
            NSToolbarFlexibleSpaceItemIdentifier,
            ITEM_SEARCH,
            ITEM_COPY,
            ITEM_EXPORT,
            ITEM_REFRESH,
            ITEM_DETAILS,
            ITEM_TOGGLE,
            ITEM_INTERVAL,
        ]

    def _build_table(self, frame: tuple[float, ...]) -> NSView:
        scroll = NSScrollView.alloc().initWithFrame_(frame)
        scroll.setHasVerticalScroller_(True)
        scroll.setHasHorizontalScroller_(True)
        scroll.setAutohidesScrollers_(True)
        scroll.setBorderType_(2)  # NSBezelBorder
        scroll.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        scroll.setWantsLayer_(True)

        table = NSTableView.alloc().initWithFrame_(scroll.bounds())
        table.setUsesAlternatingRowBackgroundColors_(True)
        table.setRowHeight_(ROW_HEIGHT)
        table.setAllowsColumnReordering_(True)
        table.setAllowsColumnResizing_(True)
        table.setAllowsMultipleSelection_(True)
        table.setGridStyleMask_(1)  # NSTableViewSolidHorizontalGridLineMask
        table.setDataSource_(self)
        table.setDelegate_(self)
        table.setDoubleAction_("rowDoubleClicked:")
        table.setTarget_(self)
        table.setMenu_(self._make_context_menu())
        scroll.setDocumentView_(table)
        self.table = table
        return scroll

    def _make_context_menu(self) -> NSMenu:
        menu = NSMenu.alloc().init()
        for title, selector in (
            ("Show Details", "rowDoubleClicked:"),
            ("Copy Row", "copyRow:"),
            ("Copy Cell", "copyCell:"),
            ("Copy Table", "copyTable:"),
            ("Copy as JSON", "copyJSON:"),
            ("Export View as CSV…", "exportCSV:"),
            ("Export Snapshot as JSON…", "exportJSON:"),
        ):
            entry = menu.addItemWithTitle_action_keyEquivalent_(title, selector, "")
            entry.setTarget_(self)
        return menu

    # -------------------------------------------------------------- callbacks
    def viewChanged_(self, sender: NSSegmentedControl) -> None:
        self._select_view(VIEWS[sender.selectedSegment()])
        self._save_preferences()

    def selectView_(self, sender: NSMenuItem) -> None:
        """``View`` menu entry: ``⌘1`` … ``⌘4`` select a view."""
        index = max(0, min(int(sender.tag()), len(VIEWS) - 1))
        self._select_view(VIEWS[index])

    def toggleAutoRefresh_(self, sender: NSButton) -> None:
        self.state.interval = self._selected_interval() if sender.state() else None
        self._schedule_timer()
        self._update_status()
        self._save_preferences()

    def toggleAutoRefreshMenu_(self, _sender: object) -> None:
        if self.auto_toggle is not None:
            self.auto_toggle.setState_(0 if self.state.interval else 1)
            self.toggleAutoRefresh_(self.auto_toggle)

    def intervalChanged_(self, _sender: NSPopUpButton) -> None:
        if self.auto_toggle is not None and self.auto_toggle.state():
            self.state.interval = self._selected_interval()
            self._schedule_timer()
        self._update_status()
        self._save_preferences()

    def searchChanged_(self, _sender: NSSearchField) -> None:
        self._apply_filter()

    def controlTextDidChange_(self, notification: object) -> None:
        """Live filtering while the user types."""
        field = getattr(notification, "object", None)
        field = field() if callable(field) else field
        if field is not None and field is self.search_field:
            self._apply_filter()

    def focusSearch_(self, _sender: object) -> None:
        if self.search_field is not None and self.window is not None:
            self.window.makeFirstResponder_(self.search_field)

    def showAbout_(self, _sender: object) -> None:
        NSApp.orderFrontStandardAboutPanel_(None)

    def showDocs_(self, _sender: object) -> None:
        NSWorkspace.sharedWorkspace().openURL_(NSURL.URLWithString_(DOCS_URL))

    def refresh_(self, _sender: object) -> None:
        try:
            snapshot = collect()
        except Exception:  # a UI must not die on a broken data source
            self._show_refresh_failure()
            return
        previous = self.state.snapshot
        self.state.changes = diff_snapshots(previous, snapshot)
        self.state.snapshot = snapshot
        self.state.reads += 1
        self.reload_table()
        self._update_menubar(changes=self.state.changes)
        self._schedule_highlight_clear()

    def _show_refresh_failure(self) -> None:
        self.status_label.setTextColor_(NSColor.systemRedColor())
        self.status_label.setStringValue_(
            "refresh failed: " + traceback.format_exc(limit=1).strip().replace("\n", " ")
        )

    def _selected_interval(self) -> float:
        if self.interval_popup is None:
            return prefs.DEFAULT_INTERVAL
        return prefs.INTERVALS[max(self.interval_popup.indexOfSelectedItem(), 0)]

    def _schedule_timer(self) -> None:
        if self.timer is not None:
            self.timer.invalidate()
            self.timer = None
        if self.state.interval:
            self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                self.state.interval, self, "refresh:", None, True
            )

    def _schedule_highlight_clear(self) -> None:
        """Clear the change highlighting after a moment (the row colour fades out)."""
        if self.fade_timer is not None:
            self.fade_timer.invalidate()
            self.fade_timer = None
        if self.state.changes.is_empty:
            return
        self.fade_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            HIGHLIGHT_SECONDS, self, "clearHighlights:", None, False
        )

    def clearHighlights_(self, _timer: object) -> None:
        self.fade_timer = None
        if self.state.changes.is_empty:
            return
        self.state.changes = ChangeSet()
        self.reload_table()

    def _apply_filter(self) -> None:
        if self.search_field is None:
            return
        self.state.filter_query = self.search_field.stringValue() or ""
        self.reload_table()

    # --------------------------------------------------------- table plumbing
    def reload_table(self) -> None:
        """Rebuild the model from the last snapshot and refresh every widget.

        The selection (tracked by row key, so it survives sorting and filtering) and
        the scroll position are restored afterwards: an auto-refresh every 2 s must
        not move the table under the user.
        """
        snapshot = self.state.snapshot
        if snapshot is None or self.window is None:
            return
        selected = self._selected_keys()
        offset = self._scroll_origin()
        self.model = self._assemble_model(snapshot)
        self.window.setTitle_(header_text(snapshot))
        self.summary_label.setStringValue_(summary_text(snapshot))
        self._rebuild_columns(self.model)
        self.empty_label.setStringValue_(
            self.model.empty_message if self.model.row_count == 0 else ""
        )
        self.table.reloadData()
        self._restore_selection(selected)
        self._restore_scroll(offset)
        self._update_status()
        self._update_menubar()

    def _selected_keys(self) -> list[str]:
        """Row keys of the current selection (stable across a rebuild)."""
        keys = []
        for row in self.table.selectedRowIndexes() or []:
            key = self._key_for_row(int(row))
            if key:
                keys.append(key)
        return keys

    def _restore_selection(self, keys: list[str]) -> None:
        if not keys or self.model is None:
            return
        wanted = set(keys)
        rows = [index for index, key in enumerate(self.model.row_keys) if key in wanted]
        if not rows:
            return
        indexes = NSMutableIndexSet.indexSet()
        for row in rows:
            indexes.addIndex_(row)
        self.table.selectRowIndexes_byExtendingSelection_(indexes, False)

    def _scroll_origin(self) -> tuple[float, float]:
        clip = self.table.enclosingScrollView().contentView()
        origin = clip.bounds().origin
        return (float(origin.x), float(origin.y))

    def _restore_scroll(self, origin: tuple[float, float]) -> None:
        if origin == (0.0, 0.0):
            return
        scroll = self.table.enclosingScrollView()
        clip = scroll.contentView()
        clip.scrollToPoint_(origin)
        scroll.reflectScrolledClipView_(clip)

    def _assemble_model(self, snapshot: Snapshot) -> TableModel:
        """Table model → filter → sort → change highlighting, in that order."""
        model = table_model(snapshot, self.state.view)
        if self.state.filter_query:
            model = filter_model(model, self.state.filter_query)
        if self.state.sort_column is not None:
            model = sort_model(model, self.state.sort_column, reverse=self.state.sort_reverse)
        return apply_changes(model, self.state.changes)

    def _rebuild_columns(self, model: TableModel) -> None:
        widths = self._current_column_widths()
        for column in list(self.table.tableColumns()):
            self.table.removeTableColumn_(column)
        for spec in model.columns:
            column = NSTableColumn.alloc().initWithIdentifier_(spec.key)
            column.headerCell().setStringValue_(spec.title)
            column.setWidth_(widths.get(spec.key, spec.width))
            column.setMinWidth_(60.0)
            if spec.sortable:
                column.setSortDescriptorPrototype_(
                    NSSortDescriptor.sortDescriptorWithKey_ascending_(spec.key, True)
                )
            self.table.addTableColumn_(column)
        if self.state.sort_column is not None and self.state.sort_column < len(model.columns):
            key = model.columns[self.state.sort_column].key
            # programmatic: without the guard this re-enters the sort handler below
            # and recurses through reload_table()
            self.syncing_sort = True
            try:
                self.table.setSortDescriptors_(
                    [
                        NSSortDescriptor.sortDescriptorWithKey_ascending_(
                            key, not self.state.sort_reverse
                        )
                    ]
                )
            finally:
                self.syncing_sort = False

    def _current_column_widths(self) -> dict[str, float]:
        widths: dict[str, float] = {}
        if self.window is None or not hasattr(self, "table"):
            return widths
        for column in self.table.tableColumns():
            widths[str(column.identifier())] = float(column.width())
        return widths

    def _update_status(self) -> None:
        if self.state.snapshot is None:
            return
        self.status_label.setTextColor_(NSColor.secondaryLabelColor())
        self.status_label.setStringValue_(
            status_text(
                self.state.snapshot,
                interval=self.state.interval,
                reads=self.state.reads,
                changes=self.state.changes,
                filter_query=self.state.filter_query,
            )
        )

    def _key_for_row(self, row: int) -> str:
        if self.model is None or row >= self.model.row_count or not self.model.row_keys:
            return ""
        return self.model.row_keys[row]

    # NSTableViewDataSource
    def numberOfRowsInTableView_(self, _table: object) -> int:
        return self.model.row_count if self.model else 0

    # NSTableViewDelegate
    def tableView_viewForTableColumn_row_(
        self, table: NSTableView, column: NSTableColumn, row: int
    ) -> NSTableCellView | None:
        if self.model is None or row >= self.model.row_count:
            return None
        index = next(
            (i for i, spec in enumerate(self.model.columns) if spec.key == column.identifier()),
            None,
        )
        if index is None:
            return None
        spec = self.model.columns[index]
        cell: Cell = self.model.rows[row][index]

        identifier = f"cell-{spec.key}"
        view = table.makeViewWithIdentifier_owner_(identifier, self)
        if view is None:
            width = column.width()
            view = NSTableCellView.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, width, ROW_HEIGHT))
            view.setIdentifier_(identifier)
            # explicit frame: an unconstrained label in a cell view has no size and
            # would render as an empty row
            field = _label(
                "",
                NSMakeRect(3.0, (ROW_HEIGHT - 15.0) / 2.0, max(width - 6.0, 20.0), 15.0),
                size=12.0,
                mono=spec.monospaced,
                mask=NSViewWidthSizable,
            )
            view.addSubview_(field)
            view.setTextField_(field)
        field = view.textField()
        numeric = spec.align is Align.RIGHT or spec.key in _NUMERIC_KEYS
        field.setAlignment_(NSTextAlignmentRight if numeric else 0)
        field.setStringValue_(cell.text)
        field.setTextColor_(_color(cell.style))
        field.setFont_(
            _mono_font(
                12.0, bold=cell.style in _BOLD_STYLES, digits=numeric and not spec.monospaced
            )
        )
        key = self._key_for_row(row)
        if key and self.state.snapshot is not None:
            view.setToolTip_(row_tooltip(self.state.snapshot, self.state.view, key) or None)
        self._tint_changed_row(view, self.model.highlight(row))
        return view

    def _tint_changed_row(self, view: NSTableCellView, highlight: Style | None) -> None:
        """Tint a changed row; the colour is cleared by :meth:`clearHighlights_`."""
        view.setWantsLayer_(True)
        layer = view.layer()
        if layer is None:  # pragma: no cover - only without a window server
            return
        if highlight is None or highlight not in _HIGHLIGHT_COLORS:
            layer.setBackgroundColor_(None)
            return
        color = getattr(NSColor, _HIGHLIGHT_COLORS[highlight])()
        layer.setBackgroundColor_(color.colorWithAlphaComponent_(0.22).CGColor())

    def tableView_sortDescriptorsDidChange_(
        self, _table: NSTableView, _notification: object
    ) -> None:
        """Column header click: sort by that column, second click reverses it."""
        if self.model is None or self.syncing_sort:
            return
        descriptors = self.table.sortDescriptors()
        if not descriptors:
            return
        descriptor = descriptors[0]
        key = str(descriptor.key())
        index = next(
            (i for i, spec in enumerate(self.model.columns) if spec.key == key),
            None,
        )
        if index is None:
            return
        self.state.sort_column = index
        self.state.sort_reverse = not bool(descriptor.ascending())
        self.reload_table()
        self._save_preferences()

    def tableViewColumnDidResize_(self, _notification: object) -> None:
        self._save_preferences()

    def showDetails_(self, _sender: object) -> None:
        """Toolbar button: the detail popover for the selected (or first) row."""
        if self.model is None or self.model.row_count == 0:
            return
        row = self.table.selectedRow()
        if row < 0:
            row = 0
        self._show_popover(row)

    def rowDoubleClicked_(self, _sender: object) -> None:
        """Double click (or ``Show Details``) opens the detail popover for the row."""
        if self.table is None:
            return
        row = self.table.clickedRow()
        if row < 0:
            row = self.table.selectedRow()
        if row >= 0:
            self._show_popover(row)

    def _show_popover(self, row: int) -> None:
        snapshot = self.state.snapshot
        key = self._key_for_row(row)
        if snapshot is None or not key or self.window is None:
            return
        pairs = detail_pairs(snapshot, self.state.view, key)
        if not pairs:
            return
        popover = NSPopover.alloc().init()
        popover.setBehavior_(NSPopoverBehaviorTransient)
        popover.setContentSize_((460.0, min(90.0 + 18.0 * len(pairs), 520.0)))
        controller = NSViewController.alloc().init()
        controller.setView_(self._make_popover_view(pairs))
        popover.setContentViewController_(controller)
        rect = self.table.rectOfRow_(row)
        popover.showRelativeToRect_ofView_preferredEdge_(rect, self.table, NSRectEdgeMaxX)
        self.popover = popover

    def _make_popover_view(self, pairs: tuple[tuple[str, str], ...]) -> NSView:
        height = min(90.0 + 18.0 * len(pairs), 520.0)
        root = NSView.alloc().initWithFrame_(NSMakeRect(0.0, 0.0, 460.0, height))
        root.setWantsLayer_(True)
        title = _label(
            f"{self.state.view.capitalize()} detail",
            NSMakeRect(14.0, height - 30.0, 430.0, 18.0),
            size=12.5,
            mono=False,
        )
        title.setFont_(NSFont.boldSystemFontOfSize_(12.5))
        root.addSubview_(title)
        y = height - 54.0
        for label, value in pairs:
            key_label = _label(f"{label}", NSMakeRect(14.0, y, 170.0, 16.0), size=11.0, mono=False)
            key_label.setTextColor_(NSColor.secondaryLabelColor())
            value_label = _label(value, NSMakeRect(188.0, y, 258.0, 16.0), size=11.0)
            root.addSubview_(key_label)
            root.addSubview_(value_label)
            y -= 18.0
        return root

    # ------------------------------------------------------------- clipboard
    def _put_on_pasteboard(self, text: str) -> bool:
        if not text:
            return False
        board = NSPasteboard.generalPasteboard()
        board.clearContents()
        board.setString_forType_(text, NSPasteboardTypeString)
        return True

    def _rows_to_copy(self) -> list[int]:
        rows = list(self.table.selectedRowIndexes() or [])
        if not rows and self.table.clickedRow() >= 0:
            rows = [self.table.clickedRow()]
        return [row for row in rows if 0 <= row < (self.model.row_count if self.model else 0)]

    def copyRow_(self, _sender: object) -> None:
        if self.model is None:
            return
        rows = self._rows_to_copy()
        text = "\n".join("\t".join(cell.text for cell in self.model.rows[row]) for row in rows)
        self._put_on_pasteboard(text or self.model.clipboard_text())

    def copyCell_(self, _sender: object) -> None:
        if self.model is None:
            return
        row, column = self.table.clickedRow(), self.table.clickedColumn()
        if 0 <= row < self.model.row_count and 0 <= column < len(self.model.columns):
            self._put_on_pasteboard(self.model.rows[row][column].text)

    def copyTable_(self, _sender: object) -> None:
        if self.model is not None:
            self._put_on_pasteboard(self.model.clipboard_text())

    def copyDetails_(self, _sender: object) -> None:
        snapshot = self.state.snapshot
        rows = self._rows_to_copy()
        if snapshot is None or not rows:
            return
        blocks = []
        for row in rows:
            pairs = detail_pairs(snapshot, self.state.view, self._key_for_row(row))
            blocks.append("\n".join(f"{label}: {value}" for label, value in pairs))
        self._put_on_pasteboard("\n\n".join(block for block in blocks if block))

    def copyJSON_(self, _sender: object) -> None:
        if self.state.snapshot is not None:
            self._put_on_pasteboard(snapshot_to_json(self.state.snapshot))

    def exportJSON_(self, _sender: object) -> None:
        if self.state.snapshot is None:
            return
        path = self._ask_for_save_path(f"usbscope-{self.state.view}.json")
        if path:
            Path(path).write_text(snapshot_to_json(self.state.snapshot) + "\n", encoding="utf-8")

    def exportCSV_(self, _sender: object) -> None:
        if self.model is None:
            return
        path = self._ask_for_save_path(f"usbscope-{self.state.view}.csv")
        if path:
            Path(path).write_text(to_csv(self.model) + "\n", encoding="utf-8")

    def _ask_for_save_path(self, name: str) -> str | None:
        panel = NSSavePanel.savePanel()
        panel.setNameFieldStringValue_(name)
        if panel.runModal() != 1:  # NSModalResponseOK
            return None
        return str(panel.URL().path())

    # window delegate
    def windowDidEndLiveResize_(self, _notification: object) -> None:
        self._save_preferences()

    def windowDidMove_(self, _notification: object) -> None:
        self._save_preferences()

    def windowWillClose_(self, _notification: object) -> None:
        self._save_preferences()


def write_png(view: NSView, path: Path) -> None:
    """Render a view hierarchy offscreen into a PNG file."""
    bounds = view.bounds()
    rep = view.bitmapImageRepForCachingDisplayInRect_(bounds)
    view.cacheDisplayInRect_toBitmapImageRep_(bounds, rep)
    data = rep.representationUsingType_properties_(NSBitmapImageFileTypePNG, {})
    data.writeToFile_atomically_(str(path), True)


def render_snapshot(
    path: Path,
    *,
    view: str = "ports",
    snapshot: Snapshot | None = None,
) -> int:
    """Build the window offscreen, render the current view to ``path`` and exit.

    The window is rendered through its theme frame, so the PNG contains the real
    titlebar and toolbar (the ``snapshot_mode`` build only means "do not touch the
    stored preferences", which keeps a capture reproducible).

    The capture uses the current system appearance: forcing an appearance (app or
    window level) invalidates the layer backed labels and they come out blank in the
    offscreen bitmap, so that flag does not exist. ``snapshot`` lets tests inject a
    fixture instead of reading the live machine.
    """
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    delegate = AppDelegate.alloc().init()
    delegate.state.view = view
    app.setDelegate_(delegate)
    delegate._build_window(show=False, snapshot_mode=True)
    delegate.state.snapshot = snapshot if snapshot is not None else collect()
    delegate.state.reads = 1
    delegate.reload_table()
    # the theme frame, not the content view: this is what makes the capture show the
    # real titlebar and toolbar instead of a hand drawn stand-in
    frame_view = delegate.window.contentView().superview()
    frame_view.layoutSubtreeIfNeeded()
    # a display pass is required for labels that were created empty and filled
    # afterwards; without it the offscreen render shows the old (empty) state
    frame_view.displayIfNeeded()
    write_png(frame_view, path)
    return 0


def run_app(*, interval: float | None = prefs.DEFAULT_INTERVAL) -> int:
    """Start the normal app event loop."""
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    delegate = AppDelegate.alloc().init()
    delegate.state.interval = interval
    delegate.state.preferences = prefs.load()
    app.setDelegate_(delegate)
    app.run()
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog="usbscope-app", description="usbscope as a native macOS app"
    )
    parser.add_argument("--snapshot", type=Path, help="render the window to a PNG and exit")
    parser.add_argument(
        "--view", choices=VIEWS, default="ports", help="view to render in --snapshot mode"
    )
    parser.add_argument(
        "--no-auto-refresh", action="store_true", help="start with auto-refresh off"
    )
    parser.add_argument(
        "--no-preferences",
        action="store_true",
        help="ignore (and do not touch) stored preferences",
    )
    parser.add_argument("--version", action="version", version=f"usbscope {__version__}")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Entry point of ``usbscope-app``."""
    args = build_parser().parse_args(argv)
    if args.snapshot:
        return render_snapshot(args.snapshot, view=args.view)
    interval = None if args.no_auto_refresh else prefs.DEFAULT_INTERVAL
    if args.no_preferences:
        app = NSApplication.sharedApplication()
        app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
        delegate = AppDelegate.alloc().init()
        delegate.use_preferences = False
        delegate.state.interval = interval
        app.setDelegate_(delegate)
        app.run()
        return 0
    return run_app(interval=interval)


if __name__ == "__main__":
    sys.exit(main())
