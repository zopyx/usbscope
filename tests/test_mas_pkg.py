"""Tests for the Mac App Store packaging script.

The script is loaded from ``scripts/`` (it is not part of the installed package) and
only its pure parts are exercised: the command plan, the identity lookup and the
refusal when the Apple certificates are missing. No signing happens here.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

SCRIPT = Path(__file__).parent.parent / "scripts" / "make_mas_pkg.py"


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("make_mas_pkg", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["make_mas_pkg"] = module
    spec.loader.exec_module(module)
    return module


mas = _load()


def test_plan_needs_both_apple_identities() -> None:
    """Without the certificates the script refuses instead of producing a broken pkg."""
    args = mas.build_parser().parse_args([])
    with pytest.raises(SystemExit) as error:
        mas.plan(args)
    message = str(error.value)
    assert "cannot package for the App Store" in message
    assert "Apple Distribution" in message
    assert "3rd Party Mac Developer Installer" in message
    assert "docs/app-store.md" in message


def test_plan_with_identities_produces_the_sandbox_signed_package() -> None:
    args = mas.build_parser().parse_args(
        [
            "--identity",
            "Apple Distribution: Andreas Jung (TEAMID)",
            "--installer-identity",
            "3rd Party Mac Developer Installer: Andreas Jung (TEAMID)",
            "--out",
            "/tmp/usbscope-test.pkg",
            "--profile",
            "/tmp/usbscope_mas.provisionprofile",
        ]
    )
    prepared = mas.plan(args)
    steps = dict(prepared.commands())

    sign = steps["sign the app (sandbox entitlements)"]
    assert sign[0] == "codesign"
    assert "--entitlements" in sign and str(mas.ENTITLEMENTS) in sign
    assert "Apple Distribution: Andreas Jung (TEAMID)" in sign
    assert "--deep" in sign and "--timestamp" in sign

    package = steps["build the installer package"]
    assert package[0] == "productbuild"
    assert "/Applications" in package
    assert "3rd Party Mac Developer Installer: Andreas Jung (TEAMID)" in package
    assert package[-1] == "/tmp/usbscope-test.pkg"

    assert "embed the provisioning profile" in steps  # profile lands in the bundle
    assert prepared.profile_target.name == "embedded.provisionprofile"
    assert steps["verify the package"][0] == "pkgutil"


def test_missing_bundle_is_reported_before_any_work() -> None:
    """A dry run still refuses a missing bundle instead of printing a plan for nothing."""
    with pytest.raises(SystemExit) as error:
        mas.main(["--dry-run", "--app", str(mas.DIST / "does-not-exist.app")])
    assert "app bundle not found" in str(error.value)


def test_dry_run_on_a_real_bundle(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    app = tmp_path / "usbscope.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_bytes(b"<plist/>")
    assert mas.main(["--dry-run", "--app", str(app)]) == 0
    out = capsys.readouterr().out
    assert "placeholder identities for the dry run" in out
    assert "codesign" in out and "productbuild" in out and "pkgutil" in out
    assert "dry run: nothing executed" in out


def test_unknown_identity_prefix_finds_nothing() -> None:
    assert mas.find_identity(prefix="No Such Certificate Authority") is None


def test_entitlements_file_requests_the_sandbox() -> None:
    import plistlib

    entitlements = plistlib.loads(mas.ENTITLEMENTS.read_bytes())
    assert entitlements == {"com.apple.security.app-sandbox": True}


def test_profile_checksum_is_sha256(tmp_path: Path) -> None:
    import hashlib

    profile = tmp_path / "usbscope.provisionprofile"
    profile.write_bytes(b"profile-bytes")
    assert mas.profile_sha256(profile) == hashlib.sha256(b"profile-bytes").hexdigest()
