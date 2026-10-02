"""Tests for the menu bar extra: pure text logic plus AppKit smoke tests.

The text builders (:func:`status_title`, :func:`status_tooltip`,
:func:`describe_changes`) run without a window server.  The widget tests build a
real ``NSStatusItem``; where the session has no usable status bar they skip
instead of failing.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, replace

import pytest

pytest.importorskip("AppKit", reason="requires the macapp extra (PyObjC)")

from AppKit import NSApplication, NSApplicationActivationPolicyAccessory

from usbscope.macapp.menubar import (
    MenuBarController,
    describe_changes,
    status_title,
    status_tooltip,
)
from usbscope.macapp.viewmodel import VIEWS
from usbscope.models import Snapshot


@dataclass(frozen=True, slots=True)
class FakeDevice:
    """A device as the notifier sees it: only a name and a vendor are needed."""

    name: str
    vendor: str | None = None


@dataclass(frozen=True, slots=True)
class FakeChanges:
    """Stand-in for the parent's ``ChangeSet`` (same duck-typed contract)."""

    added: tuple[object, ...] = ()
    removed: tuple[object, ...] = ()

    @property
    def count(self) -> int:
        """Total number of changed devices."""
        return len(self.added) + len(self.removed)


def test_notifications_require_our_own_bundle(monkeypatch: pytest.MonkeyPatch) -> None:
    """The guard compares identifiers, it does not test for presence.

    A terminal exports its own ``__CFBundleIdentifier`` (iTerm2:
    ``com.googlecode.iterm2``); ``UNUserNotificationCenter`` *aborts* the process for
    such a caller, and no ``except`` can catch a C level abort.
    """
    from usbscope.macapp.menubar import _notifications_supported

    monkeypatch.setenv("__CFBundleIdentifier", "com.googlecode.iterm2")
    assert _notifications_supported() is False

    monkeypatch.setenv("__CFBundleIdentifier", "com.zopyx.usbscope")
    assert _notifications_supported() is True

    monkeypatch.delenv("__CFBundleIdentifier", raising=False)
    assert _notifications_supported() is bool(getattr(sys, "frozen", False))


# --------------------------------------------------------------- pure text logic
def test_status_title_counts_connected_ports(snapshot: Snapshot) -> None:
    assert status_title(snapshot) == "2/6"


def test_status_title_flags_warnings(snapshot: Snapshot) -> None:
    warned = replace(snapshot, warnings=("ioreg failed",))
    assert status_title(warned) == "2/6 ⚠"


def test_status_tooltip_summarises_the_state(snapshot: Snapshot) -> None:
    tooltip = status_tooltip(snapshot)
    assert "6 port(s)" in tooltip
    assert "2 connected" in tooltip
    assert "1 device(s)" in tooltip
    assert "0 e-marked cable(s)" in tooltip
    assert tooltip.endswith("No warnings")


def test_status_tooltip_lists_warnings(snapshot: Snapshot) -> None:
    warned = replace(snapshot, warnings=("ioreg failed",))
    assert "1 warning(s): ioreg failed" in status_tooltip(warned)


def test_describe_changes_for_one_device() -> None:
    changes = FakeChanges(added=(FakeDevice("YubiKey", "Yubico"),))
    assert describe_changes(changes) == "1 device connected: YubiKey (Yubico)."


def test_describe_changes_for_two_devices() -> None:
    changes = FakeChanges(added=(FakeDevice("Keyboard", "Logitech"), FakeDevice("Mouse")))
    assert describe_changes(changes) == "2 devices connected: Keyboard (Logitech) and Mouse."


def test_describe_changes_mentions_disappeared_devices() -> None:
    changes = FakeChanges(removed=(FakeDevice("YubiKey", "Yubico"),))
    assert describe_changes(changes) == "1 device disconnected: YubiKey (Yubico)."


def test_describe_changes_is_empty_without_changes() -> None:
    assert describe_changes(FakeChanges()) == "No device changes."


# ------------------------------------------------------------------ AppKit tests
def _controller() -> MenuBarController:
    """Build a controller, or skip when the session has no usable status bar."""
    try:
        app = NSApplication.sharedApplication()
        app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        return MenuBarController(
            on_refresh=lambda: None,
            on_select_view=lambda _view: None,
            on_show_window=lambda: None,
        )
    except Exception as exc:  # pragma: no cover - headless sessions only
        pytest.skip(f"NSStatusBar is not usable in this session: {exc}")


def test_menu_exposes_every_action() -> None:
    controller = _controller()
    titles = [item.title() for item in controller.menu.itemArray()]
    assert "Open usbscope" in titles
    assert "Refresh now" in titles
    assert "Quit usbscope" in titles
    assert "Notifications on" in titles
    for view in VIEWS:
        assert view.capitalize() in titles
        assert view in controller.view_items


def test_view_checkmarks_follow_set_view() -> None:
    controller = _controller()
    for view in VIEWS:
        controller.set_view(view)
        assert controller.view == view
        for name, item in controller.view_items.items():
            expected = 1 if name == view else 0
            assert item.state() == expected, name


def test_set_view_rejects_unknown_views() -> None:
    controller = _controller()
    with pytest.raises(ValueError, match="unknown view"):
        controller.set_view("nope")


def test_update_sets_title_and_tooltip(snapshot: Snapshot) -> None:
    controller = _controller()
    controller.update(snapshot)
    assert controller.status_item.title() == "2/6"
    assert "6 port(s)" in controller.status_item.toolTip()


def test_update_with_fake_changes_does_not_raise(snapshot: Snapshot) -> None:
    controller = _controller()
    changes = FakeChanges(added=(FakeDevice("Keyboard", "Logitech"),))
    controller.update(snapshot, changes=changes)  # must not raise
    assert controller.status_item.title() == "2/6"


def test_notification_gating(snapshot: Snapshot, monkeypatch: pytest.MonkeyPatch) -> None:
    controller = _controller()
    # pretend the framework is present so the gate (not availability) is tested
    controller._notifier = object()
    controller._authorized = True
    assert controller.notifier_available

    posted: list[tuple[object, bool]] = []

    def record(device: object, *, appeared: bool) -> None:
        posted.append((device, appeared))

    monkeypatch.setattr(controller, "_post_notification", record)
    changes = FakeChanges(
        added=(FakeDevice("Keyboard", "Logitech"), FakeDevice("Mouse")),
        removed=(FakeDevice("YubiKey", "Yubico"),),
    )

    controller.set_notifications_enabled(True)
    controller.update(snapshot, changes=changes)
    assert len(posted) == 3
    assert sum(1 for _device, appeared in posted if appeared) == 2
    assert sum(1 for _device, appeared in posted if not appeared) == 1

    controller.set_notifications_enabled(False)
    assert not controller.notifications_enabled
    controller.update(snapshot, changes=changes)
    assert len(posted) == 3  # gated: nothing posted while notifications are off
