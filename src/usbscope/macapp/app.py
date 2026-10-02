"""Native macOS UI (AppKit) for usbscope.

A real Cocoa window: segmented control for the four views, view based
``NSTableView`` with monospaced values, summary header, status bar, ``⌘R``
refresh and an auto-refresh timer. No web view, no cross platform toolkit — the
UI is built from ``NSWindow``/``NSTableView``/``NSTextField``.

``usbscope-app --snapshot out.png`` renders the window offscreen to a PNG and
exits, which makes the UI verifiable (and documentable) on a machine without the
Screen Recording permission that ``screencapture`` needs.
"""

from __future__ import annotations

import argparse
import sys
import traceback
from dataclasses import dataclass, field
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
    NSFontWeightSemibold,
    NSLineBreakByTruncatingTail,
    NSMenu,
    NSMenuItem,
    NSPopUpButton,
    NSScrollView,
    NSSegmentedControl,
    NSSegmentStyleRounded,
    NSSegmentSwitchTrackingSelectOne,
    NSTableCellView,
    NSTableColumn,
    NSTableView,
    NSTextField,
    NSView,
    NSViewHeightSizable,
    NSViewMaxYMargin,
    NSViewMinXMargin,
    NSViewMinYMargin,
    NSViewWidthSizable,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
)
from Foundation import NSMakeRect, NSObject, NSTimer

from .. import __version__
from ..models import Snapshot, UsbDevice
from ..snapshot import collect
from .viewmodel import (
    VIEWS,
    Cell,
    Style,
    TableModel,
    device_tooltip,
    header_text,
    status_text,
    summary_text,
    table_model,
)

WINDOW_WIDTH = 1220.0
WINDOW_HEIGHT = 640.0
MIN_WIDTH = 900.0
MIN_HEIGHT = 420.0
ROW_HEIGHT = 22.0
MARGIN = 16.0
TOOLBAR_HEIGHT = 26.0
STATUS_HEIGHT = 16.0
INTERVALS = (1.0, 2.0, 5.0, 10.0)

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

_BOLD_STYLES = {Style.BOLD}


def _color(style: Style) -> NSColor:
    """Map a semantic style onto a system colour (dark mode aware)."""
    return getattr(NSColor, _STYLE_COLORS[style])()


def _mono_font(size: float, *, bold: bool = False) -> NSFont:
    weight = NSFontWeightSemibold if bold else 0.0
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

    view: str = "ports"
    interval: float | None = 2.0
    reads: int = 0
    snapshot: Snapshot | None = None
    extra: dict[str, object] = field(default_factory=dict)


class AppDelegate(NSObject):
    """Window, controls, table data source and refresh timer."""

    def init(self) -> AppDelegate:
        self = objc.super(AppDelegate, self).init()
        if self is None:  # pragma: no cover - Objective-C init contract
            raise RuntimeError("AppDelegate could not be initialised")
        self.state = AppState()
        self.model: TableModel | None = None
        self.timer: NSTimer | None = None
        self.window: NSWindow | None = None
        self.segments: NSSegmentedControl | None = None
        self.snapshot_mode = False
        return self

    # ------------------------------------------------------------------ setup
    def applicationDidFinishLaunching_(self, _notification: object) -> None:
        self._build_menu()
        self._build_window()
        self.refresh_(None)
        self._start_timer()
        NSApp.activate()

    def applicationShouldTerminateAfterLastWindowClosed_(self, _sender: object) -> bool:
        return True

    def quit_(self, _sender: object) -> None:
        NSApp.terminate_(None)

    def _build_menu(self) -> None:
        main_menu = NSMenu.alloc().init()
        app_item = NSMenuItem.alloc().init()
        main_menu.addItem_(app_item)
        app_menu = NSMenu.alloc().init()
        app_menu.addItemWithTitle_action_keyEquivalent_(f"About usbscope {__version__}", "", "")
        app_menu.addItemWithTitle_action_keyEquivalent_("Hide usbscope", "hide:", "h")
        app_menu.addItemWithTitle_action_keyEquivalent_("Refresh now", "refresh:", "r")
        app_menu.addItemWithTitle_action_keyEquivalent_("Quit usbscope", "terminate:", "q")
        app_item.setSubmenu_(app_menu)
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
        window.setTitle_("usbscope")
        window.setMinSize_((MIN_WIDTH, MIN_HEIGHT))
        window.center()

        self.snapshot_mode = snapshot_mode
        root = NSView.alloc().initWithFrame_(rect)
        # Layer backing: recommended for modern AppKit, and required for the
        # offscreen `--snapshot` render — without it the scroll view's layer tree
        # hides the plain sibling labels in the captured bitmap.
        root.setWantsLayer_(True)
        top = WINDOW_HEIGHT - MARGIN - TOOLBAR_HEIGHT
        self._add_toolbar(root, top)
        self.summary_label = _label(
            "",
            NSMakeRect(MARGIN, top - 8.0 - 17.0, WINDOW_WIDTH - 2.0 * MARGIN, 17.0),
            size=12.5,
            mono=False,
            mask=NSViewMinYMargin | NSViewWidthSizable,
        )
        root.addSubview_(self.summary_label)

        table_top = top - 8.0 - 17.0 - 10.0
        table_bottom = MARGIN + STATUS_HEIGHT + 14.0
        root.addSubview_(
            self._build_table(
                NSMakeRect(
                    MARGIN, table_bottom, WINDOW_WIDTH - 2.0 * MARGIN, table_top - table_bottom
                )
            )
        )

        self.empty_label = _label(
            "",
            NSMakeRect(
                MARGIN + 12.0, table_bottom - 22.0, WINDOW_WIDTH - 2.0 * MARGIN - 24.0, 16.0
            ),
            size=12.0,
            mono=False,
            mask=NSViewMinYMargin | NSViewWidthSizable,
        )
        self.empty_label.setTextColor_(NSColor.secondaryLabelColor())
        root.addSubview_(self.empty_label)

        self.status_label = _label(
            "",
            NSMakeRect(MARGIN, MARGIN, WINDOW_WIDTH - 2.0 * MARGIN, STATUS_HEIGHT),
            size=11.0,
            mask=NSViewMaxYMargin | NSViewWidthSizable,
        )
        self.status_label.setTextColor_(NSColor.secondaryLabelColor())
        root.addSubview_(self.status_label)

        window.setContentView_(root)
        self.window = window
        if show:
            window.makeKeyAndOrderFront_(None)

    def _add_toolbar(self, root: NSView, y: float) -> None:
        """Segmented view switcher on the left, auto-refresh controls on the right.

        In ``--snapshot`` mode the controls are replaced by plain labels: AppKit's
        control cells (bezel, segment titles, popup items) do not serialise into an
        offscreen bitmap, so the capture would show empty boxes. The labels carry
        the same text at the same position, and only the offscreen capture path is
        affected - the interactive app always uses the real controls.
        """
        if self.snapshot_mode:
            self.segments = None
            root.addSubview_(
                _label(
                    "  ".join(f"| {view.capitalize()}" for view in VIEWS).lstrip("| "),
                    NSMakeRect(MARGIN, y + 4.0, 432.0, 18.0),
                    size=12.0,
                    mono=False,
                    mask=NSViewMinYMargin,
                )
            )
            right = WINDOW_WIDTH - MARGIN
            root.addSubview_(
                _label(
                    "Auto-refresh   2 s      Refresh  ⌘R",
                    NSMakeRect(right - 360.0, y + 4.0, 360.0, 18.0),
                    size=12.0,
                    mono=False,
                    mask=NSViewMinXMargin | NSViewMinYMargin,
                )
            )
            return
        segments = NSSegmentedControl.alloc().initWithFrame_(
            NSMakeRect(MARGIN, y, 432.0, TOOLBAR_HEIGHT)
        )
        segments.setSegmentCount_(len(VIEWS))
        for index, view in enumerate(VIEWS):
            segments.setLabel_forSegment_(view.capitalize(), index)
            segments.setWidth_forSegment_(104.0, index)
        segments.setSegmentStyle_(NSSegmentStyleRounded)
        segments.setTrackingMode_(NSSegmentSwitchTrackingSelectOne)
        segments.setSelectedSegment_(VIEWS.index(self.state.view))
        segments.setTarget_(self)
        segments.setAction_("viewChanged:")
        segments.setAutoresizingMask_(NSViewMinYMargin)
        self.segments = segments
        root.addSubview_(segments)

        right = WINDOW_WIDTH - MARGIN
        button_width = 120.0
        popup_width = 88.0
        toggle_width = 118.0
        gap = 10.0

        button = NSButton.alloc().initWithFrame_(
            NSMakeRect(right - button_width, y, button_width, TOOLBAR_HEIGHT)
        )
        button.setTitle_("Refresh  ⌘R")
        button.setBezelStyle_(NSBezelStyleRounded)
        button.setTarget_(self)
        button.setAction_("refresh:")
        button.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        self.refresh_button = button
        root.addSubview_(button)

        popup = NSPopUpButton.alloc().initWithFrame_(
            NSMakeRect(right - button_width - gap - popup_width, y, popup_width, TOOLBAR_HEIGHT)
        )
        popup.addItemsWithTitles_([f"{value:g} s" for value in INTERVALS])
        popup.selectItemAtIndex_(
            INTERVALS.index(self.state.interval) if self.state.interval in INTERVALS else 1
        )
        popup.setTarget_(self)
        popup.setAction_("intervalChanged:")
        popup.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        self.interval_popup = popup
        root.addSubview_(popup)

        toggle = NSButton.alloc().initWithFrame_(
            NSMakeRect(
                right - button_width - gap - popup_width - gap - toggle_width,
                y,
                toggle_width,
                TOOLBAR_HEIGHT,
            )
        )
        toggle.setButtonType_(NSButtonTypeSwitch)
        toggle.setTitle_("Auto-refresh")
        toggle.setState_(1 if self.state.interval else 0)
        toggle.setTarget_(self)
        toggle.setAction_("toggleAutoRefresh:")
        toggle.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        self.auto_toggle = toggle
        root.addSubview_(toggle)

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
        table.setAllowsMultipleSelection_(True)
        table.setGridStyleMask_(1)  # NSTableViewSolidHorizontalGridLineMask
        table.setDataSource_(self)
        table.setDelegate_(self)
        scroll.setDocumentView_(table)
        self.table = table
        return scroll

    # -------------------------------------------------------------- callbacks
    def viewChanged_(self, sender: NSSegmentedControl) -> None:
        self.state.view = VIEWS[sender.selectedSegment()]
        self.reload_table()

    def toggleAutoRefresh_(self, sender: NSButton) -> None:
        self.state.interval = self._interval() if sender.state() else None
        self._start_timer()
        self._update_status()

    def intervalChanged_(self, _sender: NSPopUpButton) -> None:
        if self.auto_toggle.state():
            self.state.interval = self._interval()
            self._start_timer()
        self._update_status()

    def refresh_(self, _sender: object) -> None:
        try:
            self.state.snapshot = collect()
            self.state.reads += 1
            self.reload_table()
        except Exception:  # a UI must not die on a broken data source
            self.status_label.setTextColor_(NSColor.systemRedColor())
            self.status_label.setStringValue_(
                "refresh failed: " + traceback.format_exc(limit=1).strip().replace("\n", " ")
            )

    def _interval(self) -> float:
        return INTERVALS[max(self.interval_popup.indexOfSelectedItem(), 0)]

    def _start_timer(self) -> None:
        if self.timer is not None:
            self.timer.invalidate()
            self.timer = None
        if self.state.interval:
            self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                self.state.interval, self, "refresh:", None, True
            )

    # --------------------------------------------------------- table plumbing
    def reload_table(self) -> None:
        snapshot = self.state.snapshot
        if snapshot is None or self.window is None:
            return
        self.model = table_model(snapshot, self.state.view)
        self.window.setTitle_(header_text(snapshot))
        self.summary_label.setStringValue_(summary_text(snapshot))
        self._sync_columns(self.model)
        self.empty_label.setStringValue_(
            self.model.empty_message if self.model.row_count == 0 else ""
        )
        self.table.reloadData()
        self._update_status()

    def _sync_columns(self, model: TableModel) -> None:
        for column in list(self.table.tableColumns()):
            self.table.removeTableColumn_(column)
        for spec in model.columns:
            column = NSTableColumn.alloc().initWithIdentifier_(spec.key)
            column.headerCell().setStringValue_(spec.title)
            column.setWidth_(spec.width)
            column.setMinWidth_(60.0)
            self.table.addTableColumn_(column)

    def _update_status(self) -> None:
        if self.state.snapshot is None:
            return
        self.status_label.setTextColor_(NSColor.secondaryLabelColor())
        self.status_label.setStringValue_(
            status_text(self.state.snapshot, interval=self.state.interval, reads=self.state.reads)
        )

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
        field.setStringValue_(cell.text)
        field.setTextColor_(_color(cell.style))
        field.setFont_(_mono_font(12.0, bold=cell.style in _BOLD_STYLES))
        if spec.key in {"name", "port"}:
            device = self._device_for_row(row) if spec.key == "name" else None
            view.setToolTip_(device_tooltip(device) if device is not None else cell.text)
        return view

    def _device_for_row(self, row: int) -> UsbDevice | None:
        """The domain device behind a row of the devices view (for tooltips)."""
        snapshot = self.state.snapshot
        if snapshot is None or self.state.view != "devices":
            return None
        devices = snapshot.devices
        return devices[row] if row < len(devices) else None

    def tableView_toolTipForCell_rect_tableColumn_row_mouseLocation_(
        self,
        _table: object,
        _cell: object,
        _rect: object,
        _column: object,
        _row: int,
        _point: object,
    ) -> None:  # pragma: no cover - only reachable in a running app
        return None


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

    The capture uses the current system appearance: forcing an appearance (app or
    window level) invalidates the layer backed labels and they come out blank in
    the offscreen bitmap, so the flag was dropped instead of shipping a broken one.
    ``snapshot`` lets tests inject a fixture instead of reading the live machine.
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
    delegate.window.contentView().layoutSubtreeIfNeeded()
    # a display pass is required for labels that were created empty and filled
    # afterwards; without it the offscreen render shows the old (empty) state
    delegate.window.contentView().displayIfNeeded()
    write_png(delegate.window.contentView(), path)
    return 0


def run_app(*, interval: float | None = 2.0) -> int:
    """Start the normal app event loop."""
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    delegate = AppDelegate.alloc().init()
    delegate.state.interval = interval
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
    parser.add_argument("--version", action="version", version=f"usbscope {__version__}")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Entry point of ``usbscope-app``."""
    args = build_parser().parse_args(argv)
    if args.snapshot:
        return render_snapshot(args.snapshot, view=args.view)
    return run_app(interval=None if args.no_auto_refresh else 2.0)


if __name__ == "__main__":
    sys.exit(main())
