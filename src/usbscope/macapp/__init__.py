"""Native macOS app for usbscope (AppKit, requires the ``macapp`` extra).

Importing :mod:`usbscope.macapp.app` pulls in PyObjC/AppKit; use
:func:`usbscope.macapp.launch.main` (the ``usbscope-app`` entry point) if you want
a friendly message when the extra is not installed.
"""

from __future__ import annotations

__all__: list[str] = []
