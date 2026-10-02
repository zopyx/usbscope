#!/usr/bin/env python
"""Render the usbscope views as SVG/PNG screenshots for the README gallery.

The images are produced from a *live* snapshot of this machine (Rich exports the
recorded console as SVG, which keeps the colours and the terminal look), then
rasterised with ``rsvg-convert`` at 2x so the text stays crisp on retina screens.

Usage
-----
    uv run python scripts/screenshots.py --png          # write SVG + PNG
    uv run python scripts/screenshots.py                # SVG only
    uv run python scripts/screenshots.py --png --host mac   # mask the host name
    rsvg-convert -z 2 -o docs/screenshots/overview.png docs/screenshots/overview.svg

The SVGs are the source of truth and stay in the repository, so the gallery can be
regenerated on any Mac without a terminal emulator or a window server. Use
``--host`` before publishing captures: the header shows the real machine name
otherwise.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass, replace
from pathlib import Path

from rich import terminal_theme
from rich.console import Console
from rich.terminal_theme import TerminalTheme

from usbscope.render import build_view
from usbscope.snapshot import collect

DEFAULT_OUT = Path(__file__).resolve().parent.parent / "docs" / "screenshots"
DEFAULT_WIDTH = 140
DEFAULT_SCALE = 1.5
DEFAULT_THEME = "monokai"


@dataclass(frozen=True, slots=True)
class Shot:
    """One screenshot: file stem, view name, verbose flag and window title."""

    stem: str
    view: str
    title: str
    verbose: bool = False


SHOTS: tuple[Shot, ...] = (
    Shot("overview", "overview", "usbscope — overview"),
    Shot("ports", "ports", "usbscope ports"),
    Shot("cables", "cables", "usbscope cables"),
    Shot("devices", "devices", "usbscope devices"),
)


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        description="Render the usbscope views as SVG/PNG screenshots for the README gallery."
    )
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output directory")
    parser.add_argument(
        "--width", type=int, default=DEFAULT_WIDTH, help="terminal columns to render"
    )
    parser.add_argument(
        "--scale", type=float, default=DEFAULT_SCALE, help="rasterisation factor (e.g. 2 or 1.5)"
    )
    parser.add_argument(
        "--theme",
        default=DEFAULT_THEME,
        help="rich terminal theme name (monokai, dimmed-monokai, night-owlish, svg-export)",
    )
    parser.add_argument("--png", action="store_true", help="also rasterise with rsvg-convert")
    parser.add_argument(
        "--host",
        metavar="NAME",
        help="replace the reported host name in the captures (use when publishing them)",
    )
    return parser


def _theme(name: str) -> TerminalTheme:
    """Look a built-in Rich terminal theme up by its CLI name (e.g. night-owlish)."""
    themes = {
        key: value
        for key, value in vars(terminal_theme).items()
        if isinstance(value, TerminalTheme)
    }
    try:
        return themes[name.replace("-", "_").upper()]
    except KeyError:
        available = ", ".join(sorted(themes))
        raise SystemExit(f"unknown theme {name!r}; available: {available}") from None


def render_svg(
    shot: Shot, out_dir: Path, *, width: int, theme: TerminalTheme, host: str | None = None
) -> Path:
    """Render one view into an SVG file and return its path."""
    snapshot = collect()
    if host:
        snapshot = replace(snapshot, host=host)
    console = Console(
        record=True,
        width=width,
        force_terminal=True,
        color_system="truecolor",
        highlight=False,
        soft_wrap=False,
    )
    console.print(build_view(snapshot, console, view=shot.view, verbose=shot.verbose))
    path = out_dir / f"{shot.stem}.svg"
    console.save_svg(str(path), title=shot.title, theme=theme)
    return path


def rasterise(svg: Path, *, scale: float) -> Path:
    """Convert an SVG into a PNG using rsvg-convert."""
    png = svg.with_suffix(".png")
    result = subprocess.run(
        ["rsvg-convert", "-z", f"{scale:g}", "-a", "-o", str(png), str(svg)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"rsvg-convert failed: {result.stderr.strip()}")
    return png


def main(argv: list[str] | None = None) -> int:
    """Render every shot; returns the process exit code."""
    args = build_parser().parse_args(argv)
    if args.png and shutil.which("rsvg-convert") is None:
        print("rsvg-convert not found — install librsvg (`brew install librsvg`)", file=sys.stderr)
        return 1
    theme = _theme(args.theme)
    args.out.mkdir(parents=True, exist_ok=True)
    for shot in SHOTS:
        svg = render_svg(shot, args.out, width=args.width, theme=theme, host=args.host)
        message = f"{svg.relative_to(Path.cwd()) if svg.is_relative_to(Path.cwd()) else svg}"
        if args.png:
            png = rasterise(svg, scale=args.scale)
            message += f" + {png.name}"
        print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
