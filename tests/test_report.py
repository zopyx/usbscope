"""Tests for ``usbscope report`` (Markdown + self-contained HTML)."""

from __future__ import annotations

import hashlib
from dataclasses import replace
from datetime import datetime
from pathlib import Path

import pytest

from usbscope import cli
from usbscope.models import Snapshot
from usbscope.report import render_html, render_markdown
from usbscope.security import analyse
from usbscope.sources.storage import StorageDevice

# The fixtures snapshot with a pinned clock, so the whole report is reproducible —
# the very same two hashes are asserted by ReportsTests on the Swift side.
_FIXTURE_CLOCK = datetime.fromtimestamp(1_790_000_000)
_MARKDOWN_SHA256 = "7084b7944106eaa732564d86e70e1bf007abf1139e9fba87669c66f785ff5e69"
_HTML_SHA256 = "23f7159b0da1ec966b7484450add4423288a2ffcb1881d94f7ba853348b87cd9"


class _FakeStorage:
    """A storage source that reports nothing, so the report tests stay offline."""

    def inventory(self) -> tuple[tuple[StorageDevice, ...], tuple[str, ...]]:
        return ((), ())


def _pinned(snapshot: Snapshot) -> Snapshot:
    return replace(snapshot, seen_at=_FIXTURE_CLOCK)


# --- markdown --------------------------------------------------------------


def test_markdown_has_every_section(snapshot: Snapshot) -> None:
    text = render_markdown(snapshot)
    assert text.startswith("# usbscope report\n")
    assert "- Machine: MacBook Pro · Apple M3 Pro · macOS 27.0.1" in text
    assert "- Host: mac" in text
    assert "- Ports: 6 total · 2 connected · 0 e-marked cable(s)" in text
    assert "- Devices: 1" in text
    assert "## Ports" in text
    assert "| Port | Type | State | Mode | Cable | Devices |" in text
    assert "| USB-C@3 | USB-C | connected | USB 1.1 Full-Speed · 12 Mbit/s |" in text
    assert "## Devices" in text
    assert "| Yubico YubiKey OTP+FIDO+CCID | 0x1050:0x0407 | per-interface | 1 |" in text
    assert "## Cables" in text
    assert "## Power" in text
    assert "## Security findings" in text
    assert "composite-per-interface" in text
    assert "## USB mass storage" in text
    assert "## Warnings" in text


def test_markdown_escapes_pipes_in_cells() -> None:
    """A device name with a pipe must not break the table."""
    from usbscope.models import Bus, UsbDevice

    device = UsbDevice(name="weird|name", vendor_id=1, product_id=2, location_id=1)
    snapshot = Snapshot(
        host="mac",
        os_version="27.0.1",
        seen_at=_FIXTURE_CLOCK,
        buses=(Bus(name="bus", devices=(device,)),),
    )
    text = render_markdown(snapshot)
    assert "weird\\|name" in text


def test_markdown_empty_machine_is_honest() -> None:
    empty = Snapshot(host="mac", os_version="27.0.1", seen_at=_FIXTURE_CLOCK, model="Mac mini")
    text = render_markdown(empty)
    assert "_no receptacles reported_" in text
    assert "_no USB devices attached_" in text
    assert "_none_" in text  # warnings


# --- html ------------------------------------------------------------------


def test_html_is_self_contained(snapshot: Snapshot) -> None:
    text = render_html(snapshot)
    assert text.startswith("<!doctype html>")
    assert "<title>usbscope report</title>" in text
    assert "<style>" in text
    assert text.rstrip().endswith("</html>")
    assert "http://" not in text and "https://" not in text
    assert "<link" not in text and "<script" not in text
    assert "USB 1.1 Full-Speed" in text
    assert "composite-per-interface" in text


def test_html_escapes_markup() -> None:
    empty = Snapshot(host="a<b>&'\"", os_version="27.0.1", seen_at=_FIXTURE_CLOCK)
    text = render_html(empty)
    assert "a&lt;b&gt;&amp;&#x27;&quot;" in text


# --- determinism / cross-language parity -----------------------------------


def test_fixture_markdown_hash_is_pinned(snapshot: Snapshot) -> None:
    digest = hashlib.sha256(render_markdown(_pinned(snapshot)).encode("utf-8")).hexdigest()
    assert digest == _MARKDOWN_SHA256


def test_fixture_html_hash_is_pinned(snapshot: Snapshot) -> None:
    digest = hashlib.sha256(render_html(_pinned(snapshot)).encode("utf-8")).hexdigest()
    assert digest == _HTML_SHA256


def test_analysis_default_is_used_before_the_report(snapshot: Snapshot) -> None:
    assert render_markdown(snapshot) == render_markdown(snapshot, analyse(snapshot))


# --- CLI -------------------------------------------------------------------


def test_cli_report_prints_markdown(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], snapshot: Snapshot
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: snapshot)
    monkeypatch.setattr(cli, "StorageSource", _FakeStorage)
    assert cli.main(["report", "--no-color"]) == 0
    assert capsys.readouterr().out.startswith("# usbscope report")


def test_cli_report_writes_html_to_a_file(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    snapshot: Snapshot,
    tmp_path: Path,
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: snapshot)
    monkeypatch.setattr(cli, "StorageSource", _FakeStorage)
    target = tmp_path / "report.html"
    code = cli.main(["report", "--format", "html", "--out", str(target), "--no-color"])
    assert code == 0
    assert "report written" in capsys.readouterr().out
    assert target.read_text(encoding="utf-8").startswith("<!doctype html>")


def test_cli_report_rejects_an_unknown_format(snapshot: Snapshot) -> None:
    with pytest.raises(SystemExit):
        cli.build_parser().parse_args(["report", "--format", "pdf"])


def test_report_is_a_parser_command() -> None:
    args = cli.build_parser().parse_args(["report", "--format", "html", "--out", "x.html"])
    assert args.view == "report"
    assert args.format == "html"
    assert args.out == "x.html"
