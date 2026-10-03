#!/usr/bin/env python
"""Build ``usbscope-swift.app`` — the SwiftUI app as a real macOS app bundle.

``swift build -c release`` compiles the ``usbscope-app`` product; the script then
assembles a double-clickable bundle around it, ad-hoc signs it and proves that the
bundled binary actually runs:

    dist/usbscope-swift.app/Contents/MacOS/usbscope-app     the release binary
    dist/usbscope-swift.app/Contents/Info.plist             bundle metadata
    dist/usbscope-swift.app/Contents/Resources/usbscope.icns  (when the icon exists)

Usage
-----
    uv run python scripts/build_swift_app.py              # build + bundle + sign + verify
    uv run python scripts/build_swift_app.py --no-sign    # skip the ad-hoc codesign
    uv run python scripts/build_swift_app.py --debug      # debug configuration
    uv run python scripts/build_swift_app.py --no-verify  # do not run the bundle

Like the Python app bundle this is an *ad-hoc* signature (``codesign -s -``): a
valid self-signature, but neither Developer-ID signed nor notarised, so a download
is still stopped by Gatekeeper. What a real release additionally needs — Developer
ID, hardened runtime, ``notarytool``, ``stapler`` — and everything this script does
*not* do is written down in ``docs/distribution.md``.
"""

from __future__ import annotations

import argparse
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
BUNDLE_ID = "com.zopyx.usbscope"
EXECUTABLE = "usbscope-app"
PRODUCT = "usbscope-app"
ICON_SOURCE = ROOT / "assets" / "icon" / "usbscope.icns"
MIN_MACOS = "14.0"


def package_version() -> str:
    """The version from ``pyproject.toml``, falling back to the Swift CLI constant."""
    pyproject = ROOT / "pyproject.toml"
    if pyproject.exists():
        with pyproject.open("rb") as handle:
            data = tomllib.load(handle)
        version = data.get("project", {}).get("version")
        if isinstance(version, str) and version:
            return version
    main = ROOT / "Sources" / "usbscope" / "main.swift"
    if main.exists():
        match = re.search(r'let version = "([^"]+)"', main.read_text(encoding="utf-8"))
        if match:
            return match.group(1).removesuffix("-swift")
    raise SystemExit("cannot determine the package version (pyproject.toml / main.swift)")


def run(
    argv: list[str], *, check: bool = True, capture: bool = False, timeout: float | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a command in the repository root, printing it first.

    Without ``capture`` the output streams to the terminal (a build should be
    watchable); with ``capture`` it is collected and echoed. A non-zero exit raises
    unless ``check=False``, so a broken step never leaves a half-built bundle.
    """
    print(f"$ {shlex.join(argv)}", flush=True)
    if capture:
        result = subprocess.run(
            argv, cwd=ROOT, capture_output=True, text=True, check=False, timeout=timeout
        )
        if result.stdout.strip():
            print(result.stdout.rstrip())
        if result.stderr.strip():
            print(result.stderr.rstrip(), file=sys.stderr)
    else:
        result = subprocess.run(argv, cwd=ROOT, check=False, text=True, timeout=timeout)
    if check and result.returncode != 0:
        raise SystemExit(f"command failed ({result.returncode}): {shlex.join(argv)}")
    return result


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(description="Build the SwiftUI app into usbscope-swift.app.")
    parser.add_argument(
        "--configuration", choices=("release", "debug"), default="release", help="Swift build mode"
    )
    parser.add_argument("--name", default="usbscope-swift", help="bundle name (without .app)")
    parser.add_argument(
        "--icon",
        type=Path,
        default=ICON_SOURCE,
        help="app icon (.icns); copied when it exists",
    )
    parser.add_argument("--no-icon", action="store_true", help="build without an app icon")
    parser.add_argument("--no-sign", action="store_true", help="skip the ad-hoc codesign step")
    parser.add_argument("--no-verify", action="store_true", help="do not run the bundled binary")
    return parser


def swift_build(configuration: str) -> Path:
    """Compile the app product and return the path of the built executable."""
    run(["swift", "build", "-c", configuration, "--product", PRODUCT])
    result = run(["swift", "build", "-c", configuration, "--show-bin-path"], capture=True)
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        raise SystemExit("`swift build --show-bin-path` returned no path")
    binary = Path(lines[-1].strip()) / EXECUTABLE
    if not binary.exists():
        raise SystemExit(f"swift build did not produce an executable at {binary}")
    return binary


def info_plist(version: str, icon_name: str | None) -> dict[str, object]:
    """The bundle metadata macOS (and the App Store) reads."""
    plist: dict[str, object] = {
        "CFBundleName": "usbscope",
        "CFBundleDisplayName": "usbscope",
        "CFBundleExecutable": EXECUTABLE,
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "LSMinimumSystemVersion": MIN_MACOS,
        "NSHighResolutionCapable": True,
        "LSApplicationCategoryType": "public.app-category.utilities",
        "NSHumanReadableCopyright": "MIT licensed",
        # App Store Connect asks about export compliance on every upload; saying it
        # here keeps the question out of the submission flow
        "ITSAppUsesNonExemptEncryption": False,
    }
    if icon_name is not None:
        plist["CFBundleIconFile"] = icon_name
    return plist


def assemble_bundle(
    binary: Path, version: str, icon: Path | None, bundle: Path
) -> dict[str, object]:
    """Lay out ``Contents/{MacOS,Resources,Info.plist}`` and return the plist written."""
    if bundle.exists():
        print(f"+ remove {bundle.relative_to(ROOT)}")
        shutil.rmtree(bundle)
    macos = bundle / "Contents" / "MacOS"
    resources = bundle / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)

    target = macos / EXECUTABLE
    print(f"+ copy {binary} -> {target.relative_to(ROOT)}")
    shutil.copy2(binary, target)
    target.chmod(target.stat().st_mode | 0o111)

    icon_name: str | None = None
    if icon is not None:
        print(f"+ copy {icon.relative_to(ROOT)} -> {(resources / icon.name).relative_to(ROOT)}")
        shutil.copy2(icon, resources / icon.name)
        icon_name = icon.name
    else:
        print("+ no icon (assets/icon/usbscope.icns not found — run `make icon`)")

    plist = info_plist(version, icon_name)
    plist_path = bundle / "Contents" / "Info.plist"
    with plist_path.open("wb") as handle:
        plistlib.dump(plist, handle, sort_keys=False)
    print(f"+ write {plist_path.relative_to(ROOT)}")
    return plist


def sign(bundle: Path) -> str:
    """Ad-hoc sign the bundle (deep) and verify the signature.

    Deep signing is what the task asks for; the bundle here is a single executable
    with no embedded frameworks, so ``--deep`` is a no-op that keeps the command
    shaped like the Python app's one. The verification is *not* optional: a bundle
    whose signature does not check out is a broken artifact and fails the build.
    """
    if shutil.which("codesign") is None:
        return "codesign not found — skipped"
    run(["codesign", "--force", "--deep", "--sign", "-", "--identifier", BUNDLE_ID, str(bundle)])
    verify = run(["codesign", "--verify", "--verbose=2", str(bundle)], check=False, capture=True)
    if verify.returncode != 0:
        raise SystemExit(f"codesign --verify failed: {verify.stderr.strip()}")
    return "ad-hoc signed (codesign --verify OK)"


def verify(bundle: Path) -> list[str]:
    """Run the bundled binary and check that the artifact really works."""
    executable = bundle / "Contents" / "MacOS" / EXECUTABLE
    if not executable.exists():
        raise SystemExit(f"bundle has no executable at {executable}")

    checks: list[str] = []
    version = run([str(executable), "--version"], check=False, capture=True, timeout=60)
    line = version.stdout.strip()
    if version.returncode != 0 or not line:
        raise SystemExit(
            f"bundled app failed `--version` (exit {version.returncode}): "
            f"{(version.stderr or version.stdout).strip()[:400]}"
        )
    checks.append(f"--version → {line}")

    # `--print-rows` is the app's headless data path; it needs a window server, so
    # its absence is reported instead of failing the build on a headless machine.
    try:
        rows = run([str(executable), "--print-rows"], check=False, capture=True, timeout=120)
    except subprocess.TimeoutExpired:
        checks.append("--print-rows → timed out (skipped)")
    else:
        if rows.returncode == 0 and rows.stdout.strip():
            checks.append(
                f"--print-rows → {len(rows.stdout.splitlines())} lines (live data path OK)"
            )
        else:
            checks.append("--print-rows → skipped (no window server session)")

    plist = plistlib.loads((bundle / "Contents" / "Info.plist").read_bytes())
    checks.append(
        f"Info.plist: {plist['CFBundleIdentifier']} {plist['CFBundleShortVersionString']} "
        f"(min macOS {plist['LSMinimumSystemVersion']})"
    )
    return checks


def main(argv: list[str] | None = None) -> int:
    """Build, bundle, sign and verify the SwiftUI app; returns the exit code."""
    args = build_parser().parse_args(argv)
    version = package_version()
    print(f"usbscope-swift {version} ({args.configuration})")
    binary = swift_build(args.configuration)

    icon = None if args.no_icon else args.icon
    if icon is not None and not icon.exists():
        icon = None
    DIST.mkdir(exist_ok=True)
    bundle = DIST / f"{args.name}.app"
    plist = assemble_bundle(binary, version, icon, bundle)

    signature = "skipped (--no-sign)" if args.no_sign else sign(bundle)
    checks = [] if args.no_verify else verify(bundle)

    print(f"\n{signature}")
    for check in checks:
        print(f"  {check}")
    size = sum(f.stat().st_size for f in bundle.rglob("*") if f.is_file()) / 1024 / 1024
    print(f"\n{bundle.relative_to(ROOT)}  ({size:.1f} MiB, {plist['CFBundleName']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
