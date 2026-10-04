"""Command line interface of usbscope."""

from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from collections.abc import Sequence
from pathlib import Path

from rich.console import Console, RenderableType
from rich.live import Live
from rich.panel import Panel

from . import __version__
from .assertions import (
    ExpectationError,
    check_to_json,
    evaluate,
    parse_expectation,
    render_check,
)
from .baseline import (
    BaselineError,
    compare,
    live_document,
    load_baseline,
    render_diff,
    save_baseline,
)
from .events import event_line, iter_events, poll
from .models import Snapshot
from .render import build_security_view, build_view, render, render_security
from .report import render_html as report_html
from .report import render_markdown as report_markdown
from .security import analyse
from .serialize import security_to_json, snapshot_to_json
from .snapshot import collect
from .sources.storage import StorageDevice, StorageSource

__all__ = ["build_parser", "main"]

VIEWS = ("overview", "ports", "devices", "cables", "thunderbolt", "security", "json")

# The four automation commands. They are dispatched before the view renderer and
# keep their own exit codes: 0 ok, 3 a check/diff that did not hold, 2 a
# malformed invocation.
COMMANDS = ("check", "watch", "baseline", "report")

EPILOG = """\
views:
  overview     ports, cables, devices and USB4 receptacles (default)
  ports        USB-C / Thunderbolt port table with negotiated modes
  devices      device tree with vendor/product IDs and link modes
  cables       cable, e-marker (SOP), CC authentication, power contract, liquid detection
  thunderbolt  Thunderbolt / USB4 receptacles
  security     security findings per device/port plus the USB mass-storage inventory
  json         machine readable snapshot (same as --json)

commands (for scripts and CI):
  check        evaluate --expect assertions, exit 0/3 (2 on a malformed expectation)
  watch        --events: one JSON line per attach/detach (poll, flushed)
  baseline     save <file> | check <file>: compare the live machine to a baseline
  report       --format md|html [--out file]: human readable report

data sources: system_profiler (SPUSBHostDataType, SPThunderboltDataType,
SPPowerDataType) and ioreg -p IOPort (port controller: transports, cable e-marker,
power contract, LDCM, TRM) plus the AppleSmartBattery node (live charging power);
the security view also maps USB mass storage through diskutil.
"""


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog="usbscope",
        description="Inspect USB buses, USB-C ports, cables and negotiated link modes on macOS.",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "view",
        nargs="?",
        default="overview",
        choices=(*VIEWS, *COMMANDS),
        help="what to show (or which command to run)",
    )
    parser.add_argument(
        "rest",
        nargs="*",
        help=argparse.SUPPRESS,
        metavar="ARGS",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="show additional details")
    parser.add_argument("--json", action="store_true", help="print the snapshot as JSON")
    parser.add_argument(
        "--watch",
        type=float,
        metavar="SECONDS",
        help="refresh continuously, e.g. --watch 2 (Ctrl-C to quit)",
    )
    parser.add_argument("--no-color", action="store_true", help="disable colours")
    parser.add_argument(
        "--expect",
        action="append",
        default=None,
        metavar="EXPR",
        help="check: an expectation such as device=0x1050:0x0407, port=USB-C@3, "
        "connected>=1 (repeatable)",
    )
    parser.add_argument(
        "--events",
        action="store_true",
        help="watch: stream attach/detach events instead of refreshing the table",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        metavar="SECONDS",
        help="watch: poll interval in seconds (default 2)",
    )
    parser.add_argument(
        "--format",
        choices=("md", "html"),
        default="md",
        help="report: output format (default md)",
    )
    parser.add_argument(
        "--out",
        metavar="FILE",
        default=None,
        help="report: write to FILE instead of stdout",
    )
    parser.add_argument("--version", action="version", version=f"usbscope {__version__}")
    return parser


def _console(args: argparse.Namespace) -> Console:
    return Console(no_color=args.no_color, highlight=False, soft_wrap=False)


def _emit_json(snapshot: Snapshot) -> None:
    """Write the snapshot to stdout (plain, so it can be piped into jq)."""
    sys.stdout.write(snapshot_to_json(snapshot) + "\n")
    sys.stdout.flush()


def _storage_inventory() -> tuple[StorageDevice, ...]:
    """USB mass storage of the machine; absence is normal and never fatal."""
    storage, _warnings = StorageSource().inventory()
    return storage


def _emit_security_json(snapshot: Snapshot, storage: tuple[StorageDevice, ...]) -> None:
    """Write the security report (findings + storage) as its own JSON document."""
    payload = security_to_json(analyse(snapshot), storage, generated_at=snapshot.seen_at)
    sys.stdout.write(payload + "\n")
    sys.stdout.flush()


def _run_once(console: Console, args: argparse.Namespace, refresh: int | None) -> int:
    with console.status("[cyan]reading USB subsystem…", spinner="dots"):
        snapshot = collect()
        storage = _storage_inventory() if args.view == "security" else ()
    if args.view == "security":
        if args.json:
            _emit_security_json(snapshot, storage)
        else:
            render_security(snapshot, storage, console, verbose=args.verbose, refresh=refresh)
        return 0
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
            if args.view == "security":
                view: RenderableType = build_security_view(
                    snapshot,
                    _storage_inventory(),
                    console,
                    verbose=args.verbose,
                    refresh=refresh,
                )
            else:
                view = build_view(
                    snapshot, console, view=args.view, verbose=args.verbose, refresh=refresh
                )
            live.update(view, refresh=True)
            time.sleep(max(interval - (time.monotonic() - started), 0.0))
    return 0


def _stop_watching(_signum: int, _frame: object) -> None:
    """Leave the alternate screen cleanly when the process is asked to stop."""
    raise KeyboardInterrupt


def _check(args: argparse.Namespace) -> int:
    """Evaluate ``--expect`` assertions: exit 0 when all hold, 3 when one fails.

    A malformed expectation exits ``2`` — a typo in the test rig must never be
    reported as a failing device.
    """
    raw = args.expect or []
    if not raw:
        sys.stderr.write("usbscope check: no --expect given (nothing to check)\n")
        return 2
    try:
        expectations = [parse_expectation(item) for item in raw]
    except ExpectationError as exc:
        sys.stderr.write(f"usbscope check: {exc}\n")
        return 2
    report = evaluate(collect(), expectations)
    if args.json:
        sys.stdout.write(check_to_json(report) + "\n")
    else:
        sys.stdout.write(render_check(report) + "\n")
    return 0 if report.passed else 3


def _watch_events(args: argparse.Namespace) -> int:
    """Stream one JSON object per attach/detach, flushed after each line.

    Polling (not IOKit notifications) because the Python side has no IOKit bridge
    without PyObjC — see :mod:`usbscope.events`.
    """
    interval = max(args.interval, 0.2)
    signal.signal(signal.SIGTERM, _stop_watching)
    try:
        for event in iter_events(poll(interval, collect)):
            sys.stdout.write(event_line(event) + "\n")
            sys.stdout.flush()
    except KeyboardInterrupt:
        return 0
    return 0


def _baseline(args: argparse.Namespace) -> int:
    """``save`` a snapshot as a baseline or ``check`` the live machine against one."""
    if len(args.rest) != 2 or args.rest[0] not in {"save", "check"}:
        sys.stderr.write("usage: usbscope baseline save <file> | usbscope baseline check <file>\n")
        return 2
    action, path = args.rest
    if action == "save":
        save_baseline(collect(), path)
        sys.stdout.write(f"baseline written: {path}\n")
        return 0
    try:
        previous = load_baseline(path)
    except BaselineError as exc:
        sys.stderr.write(f"usbscope baseline: {exc}\n")
        return 2
    diff = compare(previous, live_document(collect()))
    if args.json:
        payload = json.dumps(diff.to_dict(), indent=2, ensure_ascii=False, sort_keys=True)
        sys.stdout.write(payload + "\n")
    else:
        sys.stdout.write(render_diff(diff, path) + "\n")
    return 0 if diff.identical else 3


def _report(args: argparse.Namespace) -> int:
    """Render the human readable report as Markdown or a self-contained HTML page."""
    snapshot = collect()
    storage = _storage_inventory()
    text = (
        report_html(snapshot, storage=storage)
        if args.format == "html"
        else report_markdown(snapshot, storage=storage)
    )
    if args.out:
        try:
            Path(args.out).write_text(text, encoding="utf-8")
        except OSError as exc:
            sys.stderr.write(f"usbscope report: cannot write {args.out}: {exc}\n")
            return 1
        sys.stdout.write(f"report written: {args.out}\n")
        return 0
    sys.stdout.write(text)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point; returns the process exit code."""
    args = build_parser().parse_args(argv)
    console = _console(args)
    try:
        if args.view == "check":
            return _check(args)
        if args.view == "watch":
            return _watch_events(args)
        if args.view == "baseline":
            return _baseline(args)
        if args.view == "report":
            return _report(args)
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
