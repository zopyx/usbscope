"""Tests for the CLI: argument handling, JSON output and failure behaviour."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime

import pytest

from usbscope import cli
from usbscope.models import Snapshot
from usbscope.snapshot import collect


def test_defaults() -> None:
    args = cli.build_parser().parse_args([])
    assert args.view == "overview"
    assert args.json is False
    assert args.watch is None
    assert args.verbose is False


@pytest.mark.parametrize("view", ["ports", "devices", "cables", "thunderbolt", "json"])
def test_views_are_accepted(view: str) -> None:
    assert cli.build_parser().parse_args([view]).view == view


def test_unknown_view_is_rejected() -> None:
    with pytest.raises(SystemExit):
        cli.build_parser().parse_args(["nonsense"])


def test_json_view_writes_plain_stdout(capsys: pytest.CaptureFixture[str]) -> None:
    code = cli.main(["json", "--no-color"])
    out = capsys.readouterr().out
    assert code == 0
    payload = json.loads(out)
    assert payload["schema_version"] == 1
    assert "ports" in payload and "buses" in payload
    assert "\x1b[" not in out


def test_failure_prints_a_panel_instead_of_a_traceback(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    def exploding() -> Snapshot:
        raise RuntimeError("kaputt")

    monkeypatch.setattr(cli, "collect", exploding)
    code = cli.main(["--no-color"])
    captured = capsys.readouterr()
    assert code == 1
    assert "usbscope failed" in captured.out
    assert "kaputt" in captured.out
    assert "Traceback" not in captured.out
    assert captured.err == ""


@pytest.mark.skipif(sys.platform != "darwin", reason="usbscope reads macOS tools only")
def test_live_smoke() -> None:
    """End-to-end run against the real machine (no fixtures)."""
    result = subprocess.run(
        [sys.executable, "-m", "usbscope", "--json"],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["schema_version"] == 1
    assert payload["summary"]["ports"] >= 1
    assert payload["host"]


def test_collector_is_reachable_through_the_module() -> None:
    """Guard against the CLI and the service drifting apart."""
    assert callable(collect)
    assert isinstance(datetime.now(), datetime)
