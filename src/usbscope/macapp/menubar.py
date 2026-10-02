"""Menu bar extra (``NSStatusItem``) and connect/disconnect notifications.

The status item mirrors the live state of the USB subsystem: a compact
``connected/ports`` title (plus a warning symbol), a tooltip with the full
summary, and a menu that switches the view, refreshes on demand and quits.

Device changes are announced through ``UserNotifications`` when the optional
``pyobjc-framework-UserNotifications`` package is installed.  Every failure -
missing framework, unsigned/unbundled app, denied authorisation, any exception -
degrades to a no-op and is never allowed to reach the UI.

The text rendering lives in module level functions, so it is testable without a
window server.
"""

from __future__ import annotations

import os
import sys
from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol, runtime_checkable

import objc
from AppKit import (
    NSApp,
    NSMenu,
    NSMenuItem,
    NSObject,
    NSStatusBar,
    NSVariableStatusItemLength,
)

from ..models import Snapshot
from .viewmodel import VIEWS

try:  # pragma: no cover - presence depends on the optional extra
    import UserNotifications
except ImportError:  # pragma: no cover - the notifier then stays a no-op
    UserNotifications = None

__all__ = [
    "ChangeSetLike",
    "MenuBarController",
    "describe_changes",
    "status_title",
    "status_tooltip",
]

_APP_NAME = "usbscope"
_BUNDLE_ID = "com.zopyx.usbscope"
_WARNING_SYMBOL = "⚠"


@runtime_checkable
class ChangeSetLike(Protocol):
    """Duck-typed contract of the caller's change set.

    The parent owns the concrete ``ChangeSet``; this protocol exists so the
    notifier can be written and type checked against the shape it needs, without
    importing that class.  A device is any object exposing a name-like and a
    vendor-like string through :func:`getattr`.
    """

    @property
    def added(self) -> tuple[object, ...]:
        """Devices that appeared since the previous snapshot."""
        ...

    @property
    def removed(self) -> tuple[object, ...]:
        """Devices that disappeared since the previous snapshot."""
        ...

    @property
    def count(self) -> int:
        """Total number of changed devices."""
        ...


@dataclass(frozen=True, slots=True)
class _DeviceChange:
    """Minimal :class:`ChangeSetLike` view over one device (one notification)."""

    added: tuple[object, ...] = ()
    removed: tuple[object, ...] = ()

    @property
    def count(self) -> int:
        """Number of changed devices in this view."""
        return len(self.added) + len(self.removed)


def _device_label(device: object) -> str:
    """Name plus vendor of one device, using only ``getattr``."""
    name = getattr(device, "name", None) or getattr(device, "label", None)
    vendor = getattr(device, "vendor", None)
    text = str(name) if name else "Unknown device"
    return f"{text} ({vendor})" if vendor else text


def _describe_group(devices: tuple[object, ...], verb: str) -> str:
    """One sentence for a group of appeared or disappeared devices."""
    labels = [_device_label(device) for device in devices]
    noun = "device" if len(labels) == 1 else "devices"
    if len(labels) == 1:
        listed = labels[0]
    elif len(labels) == 2:
        listed = f"{labels[0]} and {labels[1]}"
    else:
        listed = ", ".join(labels[:-1]) + f" and {labels[-1]}"
    return f"{len(labels)} {noun} {verb}: {listed}."


def describe_changes(changes: ChangeSetLike) -> str:
    """Notification body for a change set, with correct pluralisation."""
    sentences: list[str] = []
    added = tuple(changes.added)
    removed = tuple(changes.removed)
    if added:
        sentences.append(_describe_group(added, "connected"))
    if removed:
        sentences.append(_describe_group(removed, "disconnected"))
    return " ".join(sentences) if sentences else "No device changes."


def status_title(snapshot: Snapshot) -> str:
    """Compact menu bar title: connected/total ports plus a warning symbol."""
    title = f"{len(snapshot.connected_ports)}/{len(snapshot.ports)}"
    return f"{title} {_WARNING_SYMBOL}" if snapshot.warnings else title


def status_tooltip(snapshot: Snapshot) -> str:
    """Full summary shown as the status item tooltip."""
    parts = [
        f"{len(snapshot.ports)} port(s)",
        f"{len(snapshot.connected_ports)} connected",
        f"{len(snapshot.devices)} device(s)",
        f"{len(snapshot.emarked_cables)} e-marked cable(s)",
    ]
    summary = " · ".join(parts)
    if snapshot.warnings:
        return f"{summary}\n{len(snapshot.warnings)} warning(s): {'; '.join(snapshot.warnings)}"
    return f"{summary}\nNo warnings"


def _notifications_supported() -> bool:
    """True only inside our own bundle: ``UNUserNotificationCenter`` *aborts* otherwise.

    The check must compare the identifier instead of testing for presence — a
    terminal exports its own ``__CFBundleIdentifier`` (iTerm2: ``com.googlecode.iterm2``),
    and asking the notification centre from such a process kills it with a C level
    abort that no ``except`` can catch.
    """
    bundle_id = os.environ.get("__CFBundleIdentifier")  # noqa: SIM112 - spelled this way
    return bundle_id == _BUNDLE_ID or bool(getattr(sys, "frozen", False))


def _presentation_options() -> int:
    """Banner+sound options for the notification delegate (0 when unavailable)."""
    if UserNotifications is None:
        return 0
    try:
        return int(
            UserNotifications.UNNotificationPresentationOptionBanner
            | UserNotifications.UNNotificationPresentationOptionSound
        )
    except Exception:  # pragma: no cover - constant missing on older SDKs
        return 0


class _NotificationDelegate(NSObject):
    """Presents notifications even while usbscope is the frontmost app."""

    def userNotificationCenter_willPresentNotification_withCompletionHandler_(
        self,
        _center: object,
        _notification: object,
        completion_handler: Callable[[int], None],
    ) -> None:
        completion_handler(_presentation_options())


class MenuBarController:
    """Owns the ``NSStatusItem``, its menu and the change notifications."""

    def __init__(
        self,
        *,
        on_refresh: Callable[[], None],
        on_select_view: Callable[[str], None],
        on_show_window: Callable[[], None] | None = None,
    ) -> None:
        self._on_refresh = on_refresh
        self._on_select_view = on_select_view
        self._on_show_window = on_show_window
        self._view = VIEWS[0]
        self._notifications_enabled = True
        self._authorized = True
        self._notifier: object | None = None
        self._delegate: NSObject | None = None
        self._relay: _MenuActionRelay | None = None
        self._notifications_sent = 0
        self.view_items: dict[str, NSMenuItem] = {}
        self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(
            NSVariableStatusItemLength
        )
        if self.status_item is None:  # pragma: no cover - no window server
            raise RuntimeError("NSStatusBar did not return a status item")
        self.status_item.setTitle_(_APP_NAME)
        self.status_item.setToolTip_(_APP_NAME)
        self.status_item.setVisible_(True)
        self._build_menu()
        self._ensure_notifier()

    # ------------------------------------------------------------- public API
    @property
    def notifier_available(self) -> bool:
        """Whether the notification path is usable in this session."""
        return self._notifier is not None and self._authorized

    @property
    def notifications_enabled(self) -> bool:
        """Whether the user currently allows notifications (menu toggle)."""
        return self._notifications_enabled

    @property
    def view(self) -> str:
        """Currently selected view."""
        return self._view

    def set_notifications_enabled(self, enabled: bool) -> None:
        """Gate the notification path for this session and sync the menu item."""
        self._notifications_enabled = enabled
        item = getattr(self, "notifications_item", None)
        if item is not None:
            item.setState_(1 if enabled else 0)
            item.setTitle_("Notifications on" if enabled else "Notifications off")

    def set_view(self, view: str) -> None:
        """Select ``view`` (one of :data:`VIEWS`) and move the checkmark."""
        if view not in VIEWS:
            raise ValueError(f"unknown view {view!r}; expected one of {', '.join(VIEWS)}")
        self._view = view
        for name, item in self.view_items.items():
            item.setState_(1 if name == view else 0)

    def update(self, snapshot: Snapshot, *, changes: ChangeSetLike | None = None) -> None:
        """Refresh the title/tooltip from ``snapshot`` and announce ``changes``."""
        self.status_item.setTitle_(status_title(snapshot))
        self.status_item.setToolTip_(status_tooltip(snapshot))
        if changes is not None:
            self._notify(changes)

    # ---------------------------------------------------------------- actions
    def _handle_refresh(self) -> None:
        self._on_refresh()

    def _handle_select_view(self, view: str) -> None:
        self.set_view(view)
        self._on_select_view(view)

    def _handle_show_window(self) -> None:
        if self._on_show_window is not None:
            self._on_show_window()

    def _handle_toggle_notifications(self) -> None:
        self.set_notifications_enabled(not self._notifications_enabled)

    # ------------------------------------------------------------------- menu
    def _build_menu(self) -> None:
        menu = NSMenu.alloc().init()
        relay = _MenuActionRelay.alloc().initWithController_(self)
        self._relay = relay

        self.open_item = self._add_item(menu, relay, "Open usbscope", "openWindow:")
        self.open_item.setEnabled_(self._on_show_window is not None)

        for view in VIEWS:
            item = self._add_item(menu, relay, view.capitalize(), "selectView:")
            item.setRepresentedObject_(view)
            self.view_items[view] = item

        self.refresh_item = self._add_item(menu, relay, "Refresh now", "refresh:", "r")
        menu.addItem_(NSMenuItem.separatorItem())
        self.notifications_item = self._add_item(
            menu, relay, "Notifications on", "toggleNotifications:"
        )
        self.set_notifications_enabled(self._notifications_enabled)
        self.quit_item = self._add_item(menu, relay, "Quit usbscope", "quit:", "q")

        self.set_view(self._view)
        self.menu = menu
        self.status_item.setMenu_(menu)

    @staticmethod
    def _add_item(
        menu: NSMenu, target: NSObject, title: str, action: str, key: str = ""
    ) -> NSMenuItem:
        item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title, action, key)
        item.setTarget_(target)
        menu.addItem_(item)
        return item

    # ---------------------------------------------------------- notifications
    def _ensure_notifier(self) -> None:
        """Create the notification centre lazily; degrade to a no-op on failure.

        Only a bundled app is allowed to request authorisation: macOS rejects the
        request from a plain interpreter run, and asking anyway would pop a system
        prompt during a check-out run or a test.
        """
        module = UserNotifications
        if module is None or not _notifications_supported():
            return
        try:
            center = module.UNUserNotificationCenter.currentNotificationCenter()
            if center is None:
                return
            delegate = _NotificationDelegate.alloc().init()
            center.setDelegate_(delegate)
            self._delegate = delegate
            self._notifier = center
            options = module.UNAuthorizationOptionAlert | module.UNAuthorizationOptionSound
            center.requestAuthorizationWithOptions_completionHandler_(
                options, self._store_authorization
            )
        except Exception:
            self._notifier = None
            self._delegate = None
            self._authorized = False

    def _store_authorization(self, granted: bool, error: object) -> None:
        """Record the authorisation result; a refusal degrades to a no-op."""
        if error is not None or not granted:
            self._authorized = False

    def _notify(self, changes: ChangeSetLike) -> None:
        """Post one notification per appeared or disappeared device."""
        if not self._notifications_enabled or not self.notifier_available:
            return
        for device in tuple(changes.added):
            self._post_notification(device, appeared=True)
        for device in tuple(changes.removed):
            self._post_notification(device, appeared=False)

    def _post_notification(self, device: object, *, appeared: bool) -> None:
        """Post a single notification, swallowing every failure."""
        module = UserNotifications
        notifier = self._notifier
        if module is None or notifier is None:
            return
        index = self._notifications_sent
        self._notifications_sent = index + 1
        try:
            body = describe_changes(
                _DeviceChange(added=(device,)) if appeared else _DeviceChange(removed=(device,))
            )
            content = module.UNMutableNotificationContent.alloc().init()
            content.setTitle_(_APP_NAME)
            content.setSubtitle_("Device connected" if appeared else "Device disconnected")
            content.setBody_(body)
            request = module.UNNotificationRequest.requestWithIdentifier_content_trigger_(
                f"usbscope.change.{index}", content, None
            )
            post = getattr(notifier, "addNotificationRequest_withCompletionHandler_", None)
            if post is not None:
                post(request, None)
        except Exception:
            # a broken notification must never reach the UI
            self._notifier = None
            self._authorized = False


class _MenuActionRelay(NSObject):
    """Objective-C target for the status item menu (AppKit needs an ObjC object)."""

    def initWithController_(self, controller: MenuBarController) -> _MenuActionRelay:
        self = objc.super(_MenuActionRelay, self).init()
        if self is None:  # pragma: no cover - Objective-C init contract
            raise RuntimeError("_MenuActionRelay could not be initialised")
        self._controller = controller
        return self

    def openWindow_(self, _sender: object) -> None:
        self._controller._handle_show_window()

    def selectView_(self, sender: NSMenuItem) -> None:
        view = sender.representedObject()
        if isinstance(view, str):
            self._controller._handle_select_view(view)

    def refresh_(self, _sender: object) -> None:
        self._controller._handle_refresh()

    def toggleNotifications_(self, _sender: object) -> None:
        self._controller._handle_toggle_notifications()

    def quit_(self, _sender: object) -> None:
        NSApp.terminate_(None)
