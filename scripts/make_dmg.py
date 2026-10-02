#!/usr/bin/env python
"""Create a *styled* macOS disk image (DMG) for the usbscope app bundle.

Unlike a plain ``hdiutil -srcfolder`` call this script builds a proper installer
image: the app and an ``/Applications`` drop target sit in a fixed Finder window
with a background picture, a large icon size and hand-placed icons, so the user
just drags the app across.

Pipeline
--------
1. stage the ``.app`` bundle plus an ``Applications`` symlink (and the optional
   background picture) in a private scratch folder;
2. create a read-write UDRW image of the staging folder;
3. attach it and ask the Finder, best effort, to remember the window size, the
   128 px icon size, the icon positions and the background picture;
4. detach, compress to UDZO, attach the result read-only and verify it (bundle
   present, symlink resolves, bundled executable answers ``--version``, the
   background file is there when one was requested);
5. detach again, write a ``<dmg>.sha256`` sums file and print a summary.

Finder automation needs a logged-in GUI session and the "Automation" privacy
permission; when it is unavailable the layout step is reported as *skipped* with
the reason and the build still succeeds.

Usage
-----
    uv run python scripts/make_dmg.py PATH_TO_APP PATH_TO_DMG [options]

    uv run python scripts/make_dmg.py dist/usbscope.app "$TMPDIR/out.dmg"
    uv run python scripts/make_dmg.py dist/usbscope.app out.dmg --volume-name usbscope
    uv run python scripts/make_dmg.py dist/usbscope.app out.dmg --no-background
"""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKGROUND = ROOT / "assets" / "dmg" / "background.png"
BACKGROUND_DIRNAME = ".background"
BACKGROUND_NAME = "background.png"
APPLICATIONS_LINK = "/Applications"
WINDOW_BOUNDS = (200, 120, 800, 520)  # x1, y1, x2, y2 → 600 x 400 window
ICON_SIZE = 128
APP_ICON_POS = (150, 190)
LINK_ICON_POS = (450, 190)


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        description="Create a styled macOS DMG installer for a usbscope .app bundle."
    )
    parser.add_argument("app", type=Path, help="path to the .app bundle")
    parser.add_argument("dmg", type=Path, help="path of the DMG to write")
    parser.add_argument(
        "--volume-name",
        default=None,
        help="volume name of the mounted image (default: the app bundle name)",
    )
    parser.add_argument(
        "--no-background",
        action="store_true",
        help="do not add a background picture (and skip generating one)",
    )
    return parser


def _run(
    argv: list[str], *, check: bool = False, input_text: str | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a command, capturing its text output; optionally raise on failure."""
    result = subprocess.run(argv, input=input_text, capture_output=True, text=True, check=False)
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise SystemExit(f"{' '.join(argv[:3])}… failed (exit {result.returncode}):\n{detail}")
    return result


def sha256(path: Path) -> str:
    """Return the SHA-256 hex digest of a file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_background(app_name: str) -> Path | None:
    """Return the background picture, generating it with ImageMagick if needed."""
    if BACKGROUND.exists():
        print(f"background: reusing {BACKGROUND.relative_to(ROOT)}")
        return BACKGROUND
    if shutil.which("magick") is None:
        print("background: skipped — ImageMagick 'magick' not found")
        return None
    BACKGROUND.parent.mkdir(parents=True, exist_ok=True)
    font = "/System/Library/Fonts/Helvetica.ttc"
    font_args = ["-font", font] if Path(font).exists() else []
    # neutral light canvas with grey text: readable behind icons in light and dark mode
    command = [
        "magick",
        "-size",
        "600x400",
        "xc:#f4f4f6",
        "-fill",
        "#1d1d1f",
        *font_args,
        "-pointsize",
        "26",
        "-gravity",
        "north",
        "-annotate",
        "+0+34",
        app_name,
        "-fill",
        "#8a8a8e",
        *font_args,
        "-pointsize",
        "14",
        "-gravity",
        "south",
        "-annotate",
        "+0+30",
        "Drag the app onto Applications to install",
        "-stroke",
        "#b9b9c0",
        "-strokewidth",
        "3",
        "-fill",
        "none",
        "-draw",
        "path 'M 250,200 L 410,200'",
        "-draw",
        "path 'M 388,184 L 410,200 L 388,216'",
        str(BACKGROUND),
    ]
    result = _run(command)
    if result.returncode != 0 or not BACKGROUND.exists():
        print(f"background: skipped — magick failed: {(result.stderr or result.stdout).strip()}")
        return None
    print(f"background: generated {BACKGROUND.relative_to(ROOT)}")
    return BACKGROUND


def stage(app: Path, staging: Path, background: Path | None) -> str:
    """Copy the bundle and the symlink into the staging folder; return the app name."""
    app_name = app.name
    staging.mkdir(parents=True, exist_ok=True)
    _run(["ditto", str(app), str(staging / app_name)], check=True)
    link = staging / "Applications"
    if not link.is_symlink():
        os.symlink(APPLICATIONS_LINK, link)
    if background is not None:
        target_dir = staging / BACKGROUND_DIRNAME
        target_dir.mkdir(exist_ok=True)
        shutil.copyfile(background, target_dir / BACKGROUND_NAME)
    return app_name


def create_writable(staging: Path, volume_name: str, image: Path) -> None:
    """Create a read-write UDRW image of the staging folder."""
    image.unlink(missing_ok=True)
    _run(
        [
            "hdiutil",
            "create",
            "-volname",
            volume_name,
            "-srcfolder",
            str(staging),
            "-fs",
            "HFS+",
            "-format",
            "UDRW",
            "-ov",
            str(image),
        ],
        check=True,
    )


def attach(image: Path, mountpoint: Path, *, readwrite: bool) -> None:
    """Attach an image at a private mountpoint (created if necessary)."""
    mountpoint.mkdir(parents=True, exist_ok=True)
    flags = ["-noverify", "-noautoopen"]
    flags.append("-readwrite" if readwrite else "-readonly")
    _run(
        ["hdiutil", "attach", str(image), *flags, "-mountpoint", str(mountpoint)],
        check=True,
    )


def detach(mountpoint: Path) -> str:
    """Detach a mountpoint, retrying and finally forcing; return a status line."""
    last = ""
    for attempt in range(3):
        result = _run(["hdiutil", "detach", str(mountpoint)])
        if result.returncode == 0:
            return f"detached {mountpoint}"
        last = (result.stderr or result.stdout).strip()
        time.sleep(1 + attempt)
    result = _run(["hdiutil", "detach", "-force", str(mountpoint)])
    if result.returncode == 0:
        return f"force-detached {mountpoint}"
    return f"detach failed: {last or (result.stderr or result.stdout).strip()}"


def apply_layout(
    mountpoint: Path, volume_name: str, app_name: str, background: bool
) -> tuple[bool, str]:
    """Ask the Finder to store the view layout; return (applied, message).

    Finder addresses a mounted volume by the *basename of its mountpoint*, not by
    the ``-volname`` used at create time, so the caller mounts the image at a
    private directory named after the volume.
    """
    if shutil.which("osascript") is None:
        return False, "osascript not found"
    x1, y1, x2, y2 = WINDOW_BOUNDS
    app_x, app_y = APP_ICON_POS
    link_x, link_y = LINK_ICON_POS
    picture = f"{BACKGROUND_DIRNAME}:{BACKGROUND_NAME}"
    lines = [
        'tell application "Finder"',
        f'    tell disk "{volume_name}"',
        "        open",
        "        set current view of container window to icon view",
        "        set toolbar visible of container window to false",
        "        set statusbar visible of container window to false",
        "        set pathbar visible of container window to false",
        f"        set the bounds of container window to {{{x1}, {y1}, {x2}, {y2}}}",
        "        set theViewOptions to the icon view options of container window",
        "        set arrangement of theViewOptions to not arranged",
        f"        set icon size of theViewOptions to {ICON_SIZE}",
    ]
    if background:
        lines.append(f'        set background picture of theViewOptions to file "{picture}"')
    lines += [
        f'        set position of item "{app_name}" of container window to {{{app_x}, {app_y}}}',
        f'        set position of item "Applications" of container window to '
        f"{{{link_x}, {link_y}}}",
        "        update without registering applications",
        "        delay 1",
        "        close",
        "        open",
        "        update without registering applications",
        "        delay 1",
        "    end tell",
        "end tell",
    ]
    script = "\n".join(lines) + "\n"
    result = _run(["osascript", "-"], input_text=script)
    if result.returncode != 0:
        reason = (result.stderr or result.stdout).strip().splitlines()[-1] or "osascript failed"
        return False, reason
    for _ in range(10):
        if (mountpoint / ".DS_Store").exists():
            break
        time.sleep(0.3)
    if not (mountpoint / ".DS_Store").exists():
        return False, "Finder ran but wrote no .DS_Store"
    parts = "icon view, window 600x400, icon size 128, icon positions"
    if background:
        parts += ", background picture"
    return True, parts


def convert(source: Path, target: Path) -> None:
    """Convert the read-write image into a compressed UDZO image."""
    target.unlink(missing_ok=True)
    _run(
        [
            "hdiutil",
            "convert",
            str(source),
            "-format",
            "UDZO",
            "-imagekey",
            "zlib-level=9",
            "-ov",
            "-o",
            str(target),
        ],
        check=True,
    )


def verify(mountpoint: Path, app_name: str, *, background: bool) -> list[str]:
    """Verify the read-only mounted image; return check lines, raising on failure."""
    checks: list[str] = []
    failures: list[str] = []

    bundle = mountpoint / app_name
    if bundle.is_dir() and (bundle / "Contents" / "Info.plist").is_file():
        plist = plistlib.loads((bundle / "Contents" / "Info.plist").read_bytes())
        checks.append(f"app bundle present: {app_name} (id {plist.get('CFBundleIdentifier')})")
    else:
        failures.append(f"app bundle missing at {bundle}")
        plist = {}

    executable_name = plist.get("CFBundleExecutable", Path(app_name).stem)
    executable = bundle / "Contents" / "MacOS" / executable_name
    if executable.is_file():
        result = _run([str(executable), "--version"])
        version = result.stdout.strip()
        if result.returncode == 0 and version:
            checks.append(f"bundled executable runs: {version}")
        else:
            failures.append(
                f"{executable_name} --version failed: {(result.stderr or result.stdout).strip()}"
            )
    else:
        failures.append(f"executable missing at {executable}")

    link = mountpoint / "Applications"
    if link.is_symlink() and os.readlink(link) == APPLICATIONS_LINK and link.exists():
        checks.append(f"Applications symlink resolves to {APPLICATIONS_LINK}")
    else:
        target = os.readlink(link) if link.is_symlink() else "not a symlink"
        failures.append(f"Applications symlink broken (target {target!r})")

    if background:
        picture = mountpoint / BACKGROUND_DIRNAME / BACKGROUND_NAME
        if picture.is_file():
            size = picture.stat().st_size
            checks.append(f"background present: {BACKGROUND_DIRNAME}/{BACKGROUND_NAME} ({size} B)")
        else:
            failures.append(f"background missing at {BACKGROUND_DIRNAME}/{BACKGROUND_NAME}")

    if shutil.which("codesign") is not None and bundle.is_dir():
        result = _run(["codesign", "--verify", "--verbose=2", str(bundle)])
        checks.append(
            "codesign --verify: ok"
            if result.returncode == 0
            else f"codesign --verify: warning — {(result.stderr or result.stdout).strip()}"
        )

    if failures:
        raise SystemExit("verification failed:\n  " + "\n  ".join(failures))
    return checks


def main(argv: list[str] | None = None) -> int:
    """Build, style and verify the DMG; returns the process exit code."""
    args = build_parser().parse_args(argv)
    app: Path = args.app
    if not app.is_dir() or app.suffix != ".app":
        raise SystemExit(f"not an .app bundle: {app}")
    volume_name = args.volume_name or app.stem
    dmg: Path = args.dmg
    dmg.parent.mkdir(parents=True, exist_ok=True)

    scratch = Path(tempfile.mkdtemp(prefix="usbscope-dmg-"))
    staging = scratch / "staging"
    writable = scratch / "writable.dmg"
    # Finder addresses the volume by the mountpoint's basename, so name the
    # private mountpoint after the volume.
    mount_rw = scratch / (volume_name.replace("/", "-") or "usbscope-dmg")
    mount_ro = scratch / "verify"
    background_path = None if args.no_background else ensure_background(app.stem)
    app_name = stage(app, staging, background_path)
    print(f"staged {app_name} + Applications symlink in {staging}")

    attached_to: Path | None = None
    checks: list[str] = []
    try:
        create_writable(staging, volume_name, writable)
        attach(writable, mount_rw, readwrite=True)
        attached_to = mount_rw
        applied, message = apply_layout(
            mount_rw, volume_name, app_name, background_path is not None
        )
        if applied:
            print(f"Finder layout: applied — {message}")
        else:
            print(f"Finder layout: skipped — {message}")
        print(f"  {detach(mount_rw)}")
        attached_to = None

        convert(writable, dmg)
        attach(dmg, mount_ro, readwrite=False)
        attached_to = mount_ro
        checks = verify(mount_ro, app_name, background=background_path is not None)
        print(f"  {detach(mount_ro)}")
        attached_to = None
    finally:
        if attached_to is not None:
            print(f"  {detach(attached_to)}")
        shutil.rmtree(scratch, ignore_errors=True)

    for check in checks:
        print(f"  ✓ {check}")

    sums = dmg.with_name(dmg.name + ".sha256")
    sums.write_text(f"{sha256(dmg)}  {dmg.name}\n", encoding="utf-8")
    size_mib = dmg.stat().st_size / 1024 / 1024
    print(f"\n{dmg}  ({size_mib:.1f} MiB)")
    print(f"{sums}  ({sums.read_text(encoding='utf-8').strip()})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
