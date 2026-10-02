"""Entry point of ``usbscope-app``: import the AppKit UI with a readable error.

Keeping this tiny module separate means ``usbscope-app`` does not fail with a raw
``ModuleNotFoundError: AppKit`` traceback when the optional extra is missing.
"""

from __future__ import annotations

import sys

_HINT = (
    "usbscope-app needs the optional macOS UI dependency (PyObjC/AppKit).\n"
    "Install it with one of:\n"
    "  uv tool install 'usbscope[macapp]'\n"
    "  uv sync --extra macapp && uv run usbscope-app\n"
    "The CLI (`usbscope`) works without it."
)


def main(argv: list[str] | None = None) -> int:
    """Run the app, or explain what is missing."""
    try:
        from .app import main as app_main
    except ImportError as exc:  # pragma: no cover - depends on the environment
        print(f"{exc}\n\n{_HINT}", file=sys.stderr)
        return 2
    return app_main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
