"""Command line interface of usbscope."""

from __future__ import annotations

import argparse
import sys
import time
from collections.abc import Sequence

from rich.console import Console
from rich.panel import Panel

from . import __version__
from .render import render
from .serialize import snapshot_to_json
from .snapshot import collect

__all__ = ["build_parser", "main"]

VIEWS = ("overview", "ports", "devices", "cables", "thunderbolt", "json")

EPILOG = """\
views:
  overview     ports, cables, devices and USB4 receptacles (default)
  ports        USB-C / Thunderbolt port table with negotiated modes
  devices      device tree with vendor/product IDs and link modes
  cables       cable, e-marker (SOP), CC authentication and liquid detection
  thunderbolt  Thunderbolt / USB4 receptacles
  json         machine readable snapshot (same as --json)

data sources: system_profiler (SPUSBHostDataType, SPThunderboltDataType) and
ioreg -p IOPort (port controller: transports, cable e-marker, LDCM, TRM).
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


def _run_once(console: Console, args: argparse.Namespace, refresh: int | None) -> int:
    with console.status("[cyan]reading USB subsystem…", spinner="dots"):
        snapshot = collect()
    if args.json or args.view == "json":
        # plain stdout so the output can be piped into jq and friends
        sys.stdout.write(snapshot_to_json(snapshot) + "\n")
        sys.stdout.flush()
    else:
        render(snapshot, console, view=args.view, verbose=args.verbose, refresh=refresh)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point; returns the process exit code."""
    args = build_parser().parse_args(argv)
    console = _console(args)
    try:
        if not args.watch:
            return _run_once(console, args, None)
        refresh = 0
        while True:
            refresh += 1
            console.clear()
            _run_once(console, args, refresh)
            time.sleep(max(args.watch, 0.2))
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
