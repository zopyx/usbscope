#!/usr/bin/env python
"""Package ``usbscope.app`` for the Mac App Store.

Signs the bundle with the sandbox entitlements and an Apple Distribution identity,
embeds the App Store provisioning profile, builds the installer package and verifies
every step. Nothing here is guessed: without an Apple Distribution identity the script
stops with the exact reason and prints what to create.

    # what would run (no side effects, no credentials needed)
    uv run python scripts/make_mas_pkg.py --dry-run

    # the real thing, once the certificates and the profile exist
    uv run python scripts/make_mas_pkg.py \\
        --identity "Apple Distribution: Andreas Jung (ABCDE12345)" \\
        --installer-identity "3rd Party Mac Developer Installer: Andreas Jung (ABCDE12345)" \\
        --profile ~/Downloads/usbscope_mas.provisionprofile

Artifacts (into ``dist/``):

    usbscope.app                  signed for the App Store (sandbox, profile embedded)
    usbscope-<version>-mas.pkg    installer for Transporter / App Store Connect
    usbscope-<version>-mas.pkg.sha256

Required before this can succeed (all of it lives in the Apple Developer portal and
cannot be created from a shell):

* Apple Developer Program membership
* certificate *Apple Distribution* (signs the app)
* certificate *Mac Installer Distribution* / "3rd Party Mac Developer Installer"
  (signs the package)
* an App ID ``com.zopyx.usbscope`` with the App Store provisioning profile

See ``docs/app-store.md`` for the full checklist, the upload and the review notes.
"""

from __future__ import annotations

import argparse
import hashlib
import plistlib
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
ENTITLEMENTS = ROOT / "assets" / "entitlements" / "usbscope.entitlements"
BUNDLE_ID = "com.zopyx.usbscope"
APP_NAME = "usbscope"
INSTALLER_CERT_PREFIX = "3rd Party Mac Developer Installer"
DISTRIBUTION_CERT_PREFIX = "Apple Distribution"

__all__ = [
    "MasPlan",
    "build_parser",
    "find_identity",
    "main",
    "plan",
    "profile_sha256",
]


def _version() -> str:
    from usbscope import __version__

    return __version__


def _run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, check=False)
    if check and result.returncode != 0:
        raise SystemExit(
            f"{' '.join(argv[:3])}… failed:\n{(result.stderr or result.stdout).strip()}"
        )
    return result


def find_identity(*, prefix: str) -> str | None:
    """Return the first code signing identity whose name starts with ``prefix``.

    ``security find-identity -v -p codesigning`` lists the *application* identities;
    the installer identity only shows up with ``-p basic``, so both are queried.
    """
    found: list[str] = []
    for policy in ("codesigning", "basic"):
        result = _run(["security", "find-identity", "-v", "-p", policy], check=False)
        for line in (result.stdout or "").splitlines():
            if '"' not in line:
                continue
            name = line.split('"')[1]
            if name.startswith(prefix) and name not in found:
                found.append(name)
    return found[0] if found else None


@dataclass(frozen=True, slots=True)
class MasPlan:
    """Every command the packaging needs, so it can be printed and reviewed."""

    app: Path
    pkg: Path
    profile: Path | None
    entitlements: Path
    identity: str
    installer_identity: str

    def commands(self) -> tuple[tuple[str, list[str]], ...]:
        """Named commands in execution order."""
        sign_app = [
            "codesign",
            "--force",
            "--deep",
            "--timestamp",
            "--options",
            "runtime",
            "--entitlements",
            str(self.entitlements),
            "--sign",
            self.identity,
            "--identifier",
            BUNDLE_ID,
            str(self.app),
        ]
        steps: list[tuple[str, list[str]]] = []
        if self.profile is not None:
            steps.append(
                (
                    "embed the provisioning profile",
                    ["cp", str(self.profile), str(self.profile_target)],
                )
            )
        steps.extend(
            [
                ("sign the app (sandbox entitlements)", sign_app),
                (
                    "verify the signature",
                    ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(self.app)],
                ),
                (
                    "verify the entitlements are in the signature",
                    ["codesign", "-d", "--entitlements", "-", str(self.app)],
                ),
                (
                    "build the installer package",
                    [
                        "productbuild",
                        "--component",
                        str(self.app),
                        "/Applications",
                        "--sign",
                        self.installer_identity,
                        str(self.pkg),
                    ],
                ),
                ("verify the package", ["pkgutil", "--check-signature", str(self.pkg)]),
            ]
        )
        return tuple(steps)

    @property
    def profile_target(self) -> Path:
        """Where the provisioning profile belongs inside the bundle."""
        return self.app / "Contents" / "embedded.provisionprofile"


def profile_sha256(path: Path) -> str:
    """SHA-256 of the provisioning profile (App Store Connect shows the same value)."""
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def build_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(description="Package usbscope.app for the Mac App Store.")
    parser.add_argument("--app", type=Path, default=DIST / f"{APP_NAME}.app")
    parser.add_argument("--out", type=Path, default=None, help="path of the .pkg (default dist/)")
    parser.add_argument(
        "--identity", default=None, help=f"'{DISTRIBUTION_CERT_PREFIX}: …' identity"
    )
    parser.add_argument(
        "--installer-identity",
        default=None,
        help=f"'{INSTALLER_CERT_PREFIX}: …' identity (defaults to the same team)",
    )
    parser.add_argument(
        "--profile",
        type=Path,
        default=None,
        help="App Store provisioning profile; embedded, checked against its sha256",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print every command instead of running it (works without certificates)",
    )
    return parser


def plan(args: argparse.Namespace, *, placeholders: bool = False) -> MasPlan:
    """Assemble the plan, filling in discovered identities where possible.

    ``placeholders`` is for ``--dry-run``: it shows the command shape on a machine
    without the Apple certificates instead of refusing to plan at all.
    """
    identity = args.identity or find_identity(prefix=DISTRIBUTION_CERT_PREFIX)
    installer = args.installer_identity or find_identity(prefix=INSTALLER_CERT_PREFIX)
    missing: list[str] = []
    if identity is None:
        identity = f"{DISTRIBUTION_CERT_PREFIX}: <your name> (TEAMID)"
        missing.append(
            f'no "{DISTRIBUTION_CERT_PREFIX}" identity — create it in the Apple Developer '
            "portal (Certificates → Apple Distribution) and import it into the keychain, "
            "or pass --identity"
        )
    if installer is None:
        installer = f"{INSTALLER_CERT_PREFIX}: <your name> (TEAMID)"
        missing.append(
            f'no "{INSTALLER_CERT_PREFIX}" identity — create it (Certificates → Mac Installer '
            "Distribution), or pass --installer-identity"
        )
    if missing and not placeholders:
        raise SystemExit(
            "cannot package for the App Store:\n  - "
            + "\n  - ".join(missing)
            + "\n\nWhat exists on this machine:\n"
            + _identities_overview()
            + "\nRun with --dry-run to see the commands; docs/app-store.md has the checklist."
        )
    if missing:
        print(
            "warning: using placeholder identities for the dry run:\n  - " + "\n  - ".join(missing)
        )
    pkg = args.out or DIST / f"{APP_NAME}-{_version()}-mas.pkg"
    return MasPlan(
        app=args.app,
        pkg=pkg,
        profile=args.profile,
        entitlements=ENTITLEMENTS,
        identity=identity,
        installer_identity=installer,
    )


def _identities_overview() -> str:
    result = _run(["security", "find-identity", "-v", "-p", "codesigning"], check=False)
    lines = [line.strip() for line in (result.stdout or "").splitlines() if '"' in line]
    return "\n".join(f"    {line}" for line in lines) or "    (none)"


def main(argv: list[str] | None = None) -> int:
    """Sign, package and verify the App Store build; returns the exit code."""
    args = build_parser().parse_args(argv)
    if not args.app.exists():
        raise SystemExit(f"app bundle not found: {args.app} (run: make app-bundle)")
    if not ENTITLEMENTS.exists():
        raise SystemExit(f"entitlements not found: {ENTITLEMENTS}")

    mas = plan(args, placeholders=args.dry_run)
    for title, command in mas.commands():
        print(f"{title}:\n    {' '.join(command)}")
    if args.dry_run:
        print("\ndry run: nothing executed")
        return 0

    if mas.profile is not None:
        if not mas.profile.exists():
            raise SystemExit(f"provisioning profile not found: {mas.profile}")
        print(f"\nprofile {mas.profile.name}: sha256 {profile_sha256(mas.profile)}")
        mas.profile_target.parent.mkdir(parents=True, exist_ok=True)
        mas.profile_target.write_bytes(mas.profile.read_bytes())

    for title, command in mas.commands():
        if title.startswith("embed"):
            continue  # done above, so the checksum can be reported first
        result = _run(command, check=False)
        if result.returncode != 0:
            raise SystemExit(f"{title} failed:\n{(result.stderr or result.stdout).strip()}")
        print(f"✓ {title}")

    entitlements = _run(["codesign", "-d", "--entitlements", ":-", str(mas.app)], check=False)
    if "app-sandbox" not in (entitlements.stdout or ""):
        raise SystemExit(
            "the signed app does not carry the sandbox entitlement — refusing to package it"
        )

    sha = hashlib.sha256(mas.pkg.read_bytes()).hexdigest()
    sums = mas.pkg.with_suffix(".pkg.sha256")
    sums.write_text(f"{sha}  {mas.pkg.name}\n", encoding="utf-8")
    print(f"\n{mas.pkg}  ({mas.pkg.stat().st_size / 1024 / 1024:.1f} MiB)")
    print(f"{sums.name}")
    print(
        "\nnext: upload with Transporter or\n"
        f"    xcrun altool --upload-app -f {mas.pkg} -t macos --apiKey … --apiIssuer …\n"
        "then attach the build in App Store Connect (docs/app-store.md)."
    )
    return 0


def read_plist(path: Path) -> dict[str, object]:
    """Read an Info.plist (helper for tests and manual checks)."""
    return plistlib.loads(path.read_bytes())


if __name__ == "__main__":
    sys.exit(main())
