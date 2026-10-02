#!/usr/bin/env python
"""Render and package the usbscope application icon (``.icns``) from its SVG source.

The icon is authored once as a vector file; Apple's ``.icns`` container is not one.
This script bridges the two with tools that are already on the machine:

    assets/icon/usbscope.svg --rsvg-convert--> <tmp>/usbscope.iconset --iconutil--> usbscope.icns

It writes exactly the ten PNG files Apple's iconset convention expects -- 16, 32,
32, 64, 128, 256, 256, 512, 512 and 1024 pixels square -- and then compresses them
into a single ``.icns``. The intermediate iconset lives in a temporary directory, so
a run leaves only the ``.icns`` behind and running the script twice in a row is safe.

Requirements
------------
* ``rsvg-convert`` -- Homebrew: ``brew install librsvg``
* ``iconutil``     -- ships with macOS (command line tools)

Usage
-----
    uv run python scripts/make_icon.py
    uv run python scripts/make_icon.py --out build/usbscope.icns
    uv run python scripts/make_icon.py --preview 128 "$TMPDIR/icon-128.png"
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SVG = ROOT / "assets" / "icon" / "usbscope.svg"
DEFAULT_OUT = ROOT / "assets" / "icon" / "usbscope.icns"

# Apple's iconset convention: (logical size, scale factor). The pixel size is their
# product; these ten pairs yield 16, 32, 32, 64, 128, 256, 256, 512, 512 and 1024.
ICONSET_ENTRIES: tuple[tuple[int, int], ...] = (
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2),
)

_TOOL_HINTS = {
    "rsvg-convert": "install it with `brew install librsvg`",
    "iconutil": "it ships with the macOS command line tools (`xcode-select --install`)",
}


def display(path: Path) -> str:
    """Return *path* relative to the repository root when possible, else absolute."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def require_tool(name: str) -> str:
    """Return the absolute path of the *name* executable, or exit with a hint."""
    path = shutil.which(name)
    if path is None:
        hint = _TOOL_HINTS.get(name, "install it")
        raise SystemExit(f"error: {name!r} not found on PATH -- {hint}")
    return path


def run(argv: list[str]) -> None:
    """Run *argv*, turning a non-zero exit into a SystemExit carrying the tool output."""
    result = subprocess.run(argv, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip() or "(no output)"
        raise SystemExit(f"error: {argv[0]} exited with {result.returncode}\n{detail}")


def render(svg: Path, size: int, out: Path, rsvg: str) -> Path:
    """Render *svg* to a *size*x*size* PNG at *out* and return *out*."""
    out.parent.mkdir(parents=True, exist_ok=True)
    run([rsvg, "--width", str(size), "--height", str(size), "--output", str(out), str(svg)])
    return out


def entry_name(logical: int, scale: int) -> str:
    """Return the iconset file name for a logical size and scale factor."""
    suffix = "@2x" if scale == 2 else ""
    return f"icon_{logical}x{logical}{suffix}.png"


def build_iconset(svg: Path, directory: Path, rsvg: str) -> list[tuple[Path, int]]:
    """Render every iconset entry into *directory* and return the (path, pixels) pairs."""
    directory.mkdir(parents=True, exist_ok=True)
    written: list[tuple[Path, int]] = []
    for logical, scale in ICONSET_ENTRIES:
        pixels = logical * scale
        out = render(svg, pixels, directory / entry_name(logical, scale), rsvg)
        written.append((out, pixels))
    return written


def build_icns(iconset: Path, out: Path, iconutil: str) -> Path:
    """Compress *iconset* into the ``.icns`` file at *out* and return *out*."""
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)  # don't let a stale file short-circuit the build
    run([iconutil, "--convert", "icns", "--output", str(out), str(iconset)])
    return out


def preview_size(value: str) -> int:
    """Argparse type for ``--preview``: a positive integer pixel size."""
    try:
        size = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not an integer: {value!r}") from None
    if size <= 0:
        raise argparse.ArgumentTypeError(f"must be a positive number of pixels: {value!r}")
    return size


def build_parser() -> argparse.ArgumentParser:
    """Create the command line parser."""
    parser = argparse.ArgumentParser(
        prog="make_icon.py",
        description="Render and package the usbscope app icon (.icns) from its SVG source.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"where to write the .icns (default {display(DEFAULT_OUT)})",
    )
    parser.add_argument(
        "--svg",
        type=Path,
        default=DEFAULT_SVG,
        help=f"SVG source to render (default {display(DEFAULT_SVG)})",
    )
    parser.add_argument(
        "--preview",
        nargs=2,
        metavar=("SIZE", "PNG"),
        help="render a single SIZE-pixel PNG to PNG and stop (no .icns is built)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Render the icon (or a single preview PNG); returns the process exit code."""
    args = build_parser().parse_args(argv)

    svg = Path(args.svg).resolve()
    if not svg.is_file():
        raise SystemExit(f"error: SVG source not found: {svg}")
    rsvg = require_tool("rsvg-convert")

    if args.preview is not None:
        size_text, out_text = args.preview
        size = preview_size(size_text)
        out = Path(out_text).resolve()
        render(svg, size, out, rsvg)
        print(f"wrote {display(out)} ({size}x{size}, {out.stat().st_size / 1024:.1f} KiB)")
        return 0

    iconutil = require_tool("iconutil")
    out = Path(args.out).resolve()

    print(f"rendering {display(svg)}")
    with tempfile.TemporaryDirectory(prefix="usbscope-icon-") as tmp:
        iconset = Path(tmp) / f"{out.stem}.iconset"
        for path, pixels in build_iconset(svg, iconset, rsvg):
            print(f"  {path.name:22} {pixels:5}px  {path.stat().st_size / 1024:7.1f} KiB")
        build_icns(iconset, out, iconutil)

    print(f"wrote {display(out)} ({out.stat().st_size / 1024:.1f} KiB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
