"""Command line interface of usbscope."""

from __future__ import annotations

import argparse
import signal
import sys
import time
from collections.abc import Sequence

from rich.console import Console
from rich.live import Live
from rich.panel import Panel

from . import __version__
from .models import Snapshot
from .render import build_view, render
from .serialize import snapshot_to_json
from .snapshot import collect

__all__ = ["build_parser", "main"]

VIEWS = ("overview", "ports", "devices", "cables", "thunderbolt", "json")

EPILOG = """\
views:
  overview     ports, cables, devices and USB4 receptacles (default)
  ports        USB-C / Thunderbolt port table with negotiated modes
  devices      device tree with vendor/product IDs and link modes
  cables       cable, e-marker (SOP), CC authentication, power contract, liquid detection
  thunderbolt  Thunderbolt / USB4 receptacles
  json         machine readable snapshot (same as --json)

data sources: system_profiler (SPUSBHostDataType, SPThunderboltDataType,
SPPowerDataType) and ioreg -p IOPort (port controller: transports, cable e-marker,
power contract, LDCM, TRM) plus the AppleSmartBattery node (live charging power).
"""


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog="usbscope",
        description="Inspect USB buses, USB-C ports, cables and negotiated link modes on macOS.",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("view", nargs="?", default="overview", choices=VIEWS, help="what to show")
    parser.add_argument("-v", "--verbose", action="store_true", help="show additional details")
    parser.add_argument("--json", action="store_true", help="print the snapshot as JSON")
    parser.add_argument(
        "--watch",
        type=float,
        metavar="SECONDS",
        help="refresh continuously, e.g. --watch 2 (Ctrl-C to quit)",
    )
    parser.add_argument("--no-color", action="store_true", help="disable colours")
    parser.add_argument("--version", action="version", version=f"usbscope {__version__}")
    return parser


def _console(args: argparse.Namespace) -> Console:
    return Console(no_color=args.no_color, highlight=False, soft_wrap=False)


def _emit_json(snapshot: Snapshot) -> None:
    """Write the snapshot to stdout (plain, so it can be piped into jq)."""
    sys.stdout.write(snapshot_to_json(snapshot) + "\n")
    sys.stdout.flush()


def _run_once(console: Console, args: argparse.Namespace, refresh: int | None) -> int:
    with console.status("[cyan]reading USB subsystem…", spinner="dots"):
        snapshot = collect()
    if args.json or args.view == "json":
        _emit_json(snapshot)
    else:
        render(snapshot, console, view=args.view, verbose=args.verbose, refresh=refresh)
    return 0


def _watch(console: Console, args: argparse.Namespace, interval: float) -> int:
    """Refresh in place on the alternate screen — no clear/redraw flicker.

    ``Live`` repaints only the changed lines and keeps the previous frame in the
    alternate screen buffer, so the table does not flash on every refresh. The
    sleep is shortened by the time the collection took so the cadence stays even.
    """
    interval = max(interval, 0.2)
    refresh = 0
    signal.signal(signal.SIGTERM, _stop_watching)
    with Live(
        console=console,
        screen=True,
        auto_refresh=False,
        vertical_overflow="crop",
        transient=False,
    ) as live:
        while True:
            refresh += 1
            started = time.monotonic()
            snapshot = collect()
            live.update(
                build_view(
                    snapshot, console, view=args.view, verbose=args.verbose, refresh=refresh
                ),
                refresh=True,
            )
            time.sleep(max(interval - (time.monotonic() - started), 0.0))
    return 0


def _stop_watching(_signum: int, _frame: object) -> None:
    """Leave the alternate screen cleanly when the process is asked to stop."""
    raise KeyboardInterrupt


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point; returns the process exit code."""
    args = build_parser().parse_args(argv)
    console = _console(args)
    try:
        wants_json = args.json or args.view == "json"
        if args.watch and not wants_json:
            return _watch(console, args, args.watch)
        return _run_once(console, args, None)
    except KeyboardInterrupt:
        console.print("[dim]stopped[/]")
        return 0
    except Exception as exc:
        console.print(
            Panel(
                f"[red]{exc}[/]\n[dim]re-run with -v/--verbose … or check that "
                "[cyan]system_profiler[/] and [cyan]ioreg[/] are available.[/]",
                title="[red]usbscope failed[/]",
                border_style="red",
            )
        )
        return 1
