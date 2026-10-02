"""Persistent app preferences (``NSUserDefaults``).

The app remembers the selected view, the refresh cadence, the window frame, the
sort state and the column widths, so a restart looks like the last session. The
store is injected as a small protocol, which keeps the logic testable without
touching the real user defaults.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Protocol, cast

from .viewmodel import VIEWS

__all__ = ["DOMAIN", "INTERVALS", "KEY", "DefaultsLike", "Preferences", "load", "save"]

KEY = "preferences"
DOMAIN = "com.zopyx.usbscope"
INTERVALS = (1.0, 2.0, 5.0, 10.0)
DEFAULT_INTERVAL = 2.0


class DefaultsLike(Protocol):
    """The slice of ``NSUserDefaults`` this module uses."""

    def objectForKey_(self, key: str) -> object:
        """Return the stored value or ``None``."""
        ...

    def setObject_forKey_(self, value: object, key: str) -> None:
        """Store a plist-compatible value."""
        ...


@dataclass(slots=True)
class Preferences:
    """Everything the app remembers between launches."""

    view: str = VIEWS[0]
    interval: float | None = DEFAULT_INTERVAL
    window_frame: tuple[float, float, float, float] | None = None
    sort_column: int | None = None
    sort_reverse: bool = False
    notifications: bool = True
    column_widths: dict[str, float] = field(default_factory=dict)

    def sanitized(self) -> Preferences:
        """Return a copy with invalid values replaced by defaults.

        The defaults file is user-writable, so nothing read from it is trusted.
        """
        view = self.view if self.view in VIEWS else VIEWS[0]
        interval = (
            self.interval
            if self.interval in INTERVALS or self.interval is None
            else DEFAULT_INTERVAL
        )
        frame = self.window_frame
        if frame is not None and (len(frame) != 4 or not all(_is_number(part) for part in frame)):
            frame = None
        if frame is not None and (frame[2] < 400 or frame[3] < 300):
            frame = None
        widths = {
            str(key): number
            for key, value in (self.column_widths or {}).items()
            if (number := _as_number(value)) is not None and number >= 30.0
        }
        sort_column = (
            self.sort_column
            if isinstance(self.sort_column, int) and 0 <= self.sort_column <= 20
            else None
        )
        return Preferences(
            view=view,
            interval=interval,
            window_frame=frame,
            sort_column=sort_column,
            sort_reverse=bool(self.sort_reverse),
            notifications=bool(self.notifications),
            column_widths=widths,
        )

    def as_dict(self) -> dict[str, Any]:
        """plist-compatible representation (tuples become lists, nulls stay out).

        ``NSUserDefaults`` refuses a property list holding a null, so "auto-refresh
        off" is stored as ``0`` rather than as ``None``; a missing key means "never
        stored" and falls back to the default.
        """
        data: dict[str, Any] = {
            key: value for key, value in asdict(self).items() if value is not None
        }
        data["interval"] = 0.0 if self.interval is None else float(self.interval)
        if self.window_frame:
            data["window_frame"] = [float(part) for part in self.window_frame]
        return data


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def load(defaults: DefaultsLike | None = None) -> Preferences:
    """Read the stored preferences, falling back to defaults."""
    if defaults is None:
        defaults = _system_defaults()
    raw = defaults.objectForKey_(KEY) if defaults is not None else None
    if not isinstance(raw, dict):
        return Preferences()
    frame = raw.get("window_frame")
    frame_tuple = (
        (float(frame[0]), float(frame[1]), float(frame[2]), float(frame[3]))
        if isinstance(frame, list) and len(frame) == 4 and all(_is_number(part) for part in frame)
        else None
    )
    return Preferences(
        view=str(raw.get("view", VIEWS[0])),
        interval=_interval(raw["interval"]) if "interval" in raw else DEFAULT_INTERVAL,
        window_frame=frame_tuple,
        sort_column=raw.get("sort_column") if isinstance(raw.get("sort_column"), int) else None,
        sort_reverse=bool(raw.get("sort_reverse", False)),
        notifications=bool(raw.get("notifications", True)),
        column_widths={
            str(key): number
            for key, value in (raw.get("column_widths") or {}).items()
            if (number := _as_number(value)) is not None
        },
    ).sanitized()


def save(preferences: Preferences, defaults: DefaultsLike | None = None) -> None:
    """Store ``preferences``."""
    if defaults is None:
        defaults = _system_defaults()
    if defaults is None:
        return
    defaults.setObject_forKey_(preferences.sanitized().as_dict(), KEY)


def _as_number(value: object) -> float | None:
    """Return ``value`` as a float when it is a real number, else ``None``."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(cast("float", value))
    return None


def _interval(value: object) -> float | None:
    """Read the stored cadence: ``0`` means off, missing or unusable means the default."""
    if value is None:
        return None
    if _as_number(value) == 0.0:
        return None
    number = _as_number(value)
    return number if number is not None else DEFAULT_INTERVAL


def _system_defaults() -> DefaultsLike | None:
    """Return the defaults domain for ``com.zopyx.usbscope`` when AppKit is importable.

    The suite form is used instead of ``standardUserDefaults`` so a check-out run
    (``uv run usbscope-app``) and the bundled app write the same domain, and so a
    script run can never end up in the global domain.
    """
    try:
        from Foundation import NSUserDefaults
    except ImportError:
        return None
    suite = NSUserDefaults.alloc().initWithSuiteName_(DOMAIN)
    return suite if suite is not None else NSUserDefaults.standardUserDefaults()
