"""Tests for ``usbscope baseline`` (save + check)."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

import pytest

from usbscope import cli
from usbscope.baseline import (
    BaselineDiff,
    BaselineError,
    compare,
    live_document,
    load_baseline,
    render_diff,
    save_baseline,
)
from usbscope.models import Cable, Port, Snapshot, UsbDevice
from usbscope.serialize import snapshot_to_dict

_WHEN = datetime(2026, 10, 2, 12, 0, 0)


def _device(
    name: str = "Gadget", *, location_id: int | None = 1, port: str | None = "USB-C@3"
) -> UsbDevice:
    return UsbDevice(
        name=name, vendor_id=0x1050, product_id=0x0407, location_id=location_id, port=port
    )


def _port(name: str = "USB-C@3", *, connected: bool = True, mode: str | None = None) -> Port:
    device = (_device(port=name),) if connected else ()
    return Port(
        description=f"Port-{name}",
        kind="USB-C",
        number=3,
        connected=connected,
        cable=Cable(attached=connected),
        devices=device,
    )


def _snapshot(*, ports: tuple[Port, ...] = (), devices: tuple[UsbDevice, ...] = ()) -> Snapshot:
    from usbscope.models import Bus

    buses = (Bus(name="USB 3.1 Bus", devices=devices),) if devices else ()
    return Snapshot(host="mac", os_version="27.0.1", seen_at=_WHEN, ports=ports, buses=buses)


def _document(
    *, ports: list[dict[str, object]] | None = None, buses: list[dict[str, object]] | None = None
) -> dict[str, object]:
    return {
        "schema_version": 1,
        "host": "mac",
        "seen_at": "2026-10-02T12:00:00",
        "ports": ports or [],
        "buses": buses or [],
    }


def _port_doc(
    name: str = "USB-C@3", *, connected: bool = True, mode: str = "full_speed"
) -> dict[str, object]:
    return {
        "name": name,
        "connected": connected,
        "mode": mode,
        "cable": {"kind": "e-marked" if connected else "–"},
        "liquid_detected": False,
        "devices": [{"name": "Gadget", "location_id": 1}] if connected else [],
    }


# --- save / load -----------------------------------------------------------


def test_save_and_load_round_trip(tmp_path: Path) -> None:
    path = tmp_path / "base.json"
    save_baseline(_snapshot(ports=(_port(),)), path)
    payload = load_baseline(path)
    assert payload["schema_version"] == 1
    assert payload["ports"][0]["name"] == "USB-C@3"
    assert path.read_text(encoding="utf-8").endswith("\n")


def test_save_writes_the_snapshot_document(tmp_path: Path) -> None:
    path = tmp_path / "base.json"
    snapshot = _snapshot(ports=(_port(),))
    save_baseline(snapshot, path)
    assert json.loads(path.read_text(encoding="utf-8")) == snapshot_to_dict(snapshot)


def test_load_missing_file_raises(tmp_path: Path) -> None:
    with pytest.raises(BaselineError):
        load_baseline(tmp_path / "nope.json")


def test_load_invalid_json_raises(tmp_path: Path) -> None:
    path = tmp_path / "bad.json"
    path.write_text("{not json", encoding="utf-8")
    with pytest.raises(BaselineError):
        load_baseline(path)


def test_load_non_snapshot_raises(tmp_path: Path) -> None:
    path = tmp_path / "other.json"
    path.write_text(json.dumps({"hello": "world"}), encoding="utf-8")
    with pytest.raises(BaselineError):
        load_baseline(path)


# --- comparison ------------------------------------------------------------


def test_identical_documents_report_no_difference() -> None:
    document = _document(ports=[_port_doc()])
    diff = compare(document, document)
    assert diff.identical
    assert render_diff(diff, "base.json").endswith("identical to baseline")


def test_seen_at_alone_is_ignored() -> None:
    document = _document(ports=[_port_doc()])
    moved = {**document, "seen_at": "2026-10-03T09:00:00"}
    assert compare(document, moved).identical


def test_appeared_disappeared_and_changed_ports() -> None:
    previous = _document(ports=[_port_doc("USB-C@1"), _port_doc("USB-C@3")])
    current = _document(ports=[_port_doc("USB-C@3", connected=False), _port_doc("USB-C@4")])
    diff = compare(previous, current)
    assert diff.appeared_ports == ("USB-C@4",)
    assert diff.disappeared_ports == ("USB-C@1",)
    assert diff.changed_ports == ("USB-C@3",)
    assert not diff.identical


def test_device_appearance_is_reported() -> None:
    previous = _document(buses=[])
    current = _document(buses=[{"devices": [{"name": "Stick", "location_id": 7}]}])
    diff = compare(previous, current)
    assert diff.appeared_devices == ("loc:7",)
    assert not diff.identical


def test_device_identity_falls_back_to_name_without_location() -> None:
    previous = _document()
    current = _document(buses=[{"devices": [{"name": "Nameless", "location_id": None}]}])
    diff = compare(previous, current)
    assert diff.appeared_devices == ("name:Nameless",)


def test_render_diff_lists_each_group() -> None:
    previous = _document(ports=[_port_doc("USB-C@1")])
    current = _document(ports=[_port_doc("USB-C@2")])
    text = render_diff(compare(previous, current), "base.json")
    assert "disappeared ports: USB-C@1" in text
    assert "appeared ports: USB-C@2" in text
    assert text.endswith("differs from baseline")


def test_diff_to_dict_is_stable() -> None:
    diff = BaselineDiff(appeared_ports=("USB-C@4",))
    payload = diff.to_dict()
    assert payload["kind"] == "baseline"
    assert payload["identical"] is False
    assert payload["appeared_ports"] == ["USB-C@4"]


# --- CLI -------------------------------------------------------------------


def test_cli_baseline_save_then_check_identical(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    snapshot = _snapshot(ports=(_port(),))
    monkeypatch.setattr(cli, "collect", lambda: snapshot)
    path = tmp_path / "base.json"
    assert cli.main(["baseline", "save", str(path), "--no-color"]) == 0
    assert "baseline written" in capsys.readouterr().out
    assert cli.main(["baseline", "check", str(path), "--no-color"]) == 0
    assert "identical to baseline" in capsys.readouterr().out


def test_cli_baseline_check_reports_a_difference(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    path = tmp_path / "base.json"
    save_baseline(_snapshot(ports=(_port("USB-C@3"),)), path)
    monkeypatch.setattr(cli, "collect", lambda: _snapshot(ports=(_port("USB-C@4"),)))
    code = cli.main(["baseline", "check", str(path), "--no-color"])
    assert code == 3
    out = capsys.readouterr().out
    assert "appeared ports: USB-C@4" in out
    assert "disappeared ports: USB-C@3" in out


def test_cli_baseline_check_unreadable_exits_two(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot())
    code = cli.main(["baseline", "check", str(tmp_path / "nope.json"), "--no-color"])
    assert code == 2
    assert "cannot read baseline" in capsys.readouterr().err


def test_cli_baseline_without_action_exits_two(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot())
    assert cli.main(["baseline", "--no-color"]) == 2
    assert "usage: usbscope baseline" in capsys.readouterr().err


def test_cli_baseline_json(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    path = tmp_path / "base.json"
    save_baseline(_snapshot(ports=(_port("USB-C@3"),)), path)
    monkeypatch.setattr(cli, "collect", lambda: _snapshot(ports=(_port("USB-C@4"),)))
    code = cli.main(["baseline", "check", str(path), "--json", "--no-color"])
    assert code == 3
    payload = json.loads(capsys.readouterr().out)
    assert payload["kind"] == "baseline"
    assert payload["appeared_ports"] == ["USB-C@4"]


def test_live_document_matches_the_file_format() -> None:
    snapshot = _snapshot(ports=(_port(),))
    assert live_document(snapshot) == snapshot_to_dict(snapshot)


def test_baseline_is_a_parser_command() -> None:
    args = cli.build_parser().parse_args(["baseline", "save", "x.json"])
    assert args.view == "baseline"
    assert args.rest == ["save", "x.json"]
