"""Tests for ``usbscope check`` (assertions / CI mode)."""

from __future__ import annotations

import json
from datetime import datetime

import pytest

from usbscope import cli
from usbscope.assertions import (
    CheckReport,
    ExpectationError,
    check_to_json,
    device_matches,
    evaluate,
    normalize_usb_id,
    parse_expectation,
    render_check,
)
from usbscope.models import Bus, Port, Snapshot, UsbDevice

_WHEN = datetime(2026, 10, 2, 12, 0, 0)


def _device(
    name: str = "Gadget",
    *,
    vendor: str | None = None,
    vendor_id: int | None = 0x1050,
    product_id: int | None = 0x0407,
    serial: str | None = None,
    location_id: int | None = 1,
    port: str | None = None,
) -> UsbDevice:
    return UsbDevice(
        name=name,
        vendor=vendor,
        vendor_id=vendor_id,
        product_id=product_id,
        serial=serial,
        location_id=location_id,
        port=port,
    )


def _port(name: str = "USB-C@3", *, connected: bool = True) -> Port:
    return Port(description=f"Port-{name}", kind="USB-C", number=3, connected=connected)


def _snapshot(
    *,
    devices: tuple[UsbDevice, ...] = (),
    ports: tuple[Port, ...] = (),
    warnings: tuple[str, ...] = (),
) -> Snapshot:
    buses = (Bus(name="USB 3.1 Bus", devices=devices),) if devices else ()
    return Snapshot(
        host="mac", os_version="27.0.1", seen_at=_WHEN, ports=ports, buses=buses, warnings=warnings
    )


# --- parsing ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("expression", "key", "op", "value", "target"),
    [
        ("device=0x1050:0x0407", "device", "=", "0x1050:0x0407", None),
        ("device=YubiKey", "device", "=", "YubiKey", None),
        ("port=USB-C@3", "port", "=", "USB-C@3", None),
        ("connected>=1", "connected", ">=", "1", 1),
        ("devices>=2", "devices", ">=", "2", 2),
        ("warning=0", "warning", "=", "0", 0),
        ("warnings<=3", "warnings", "<=", "3", 3),
        ("devices<10", "devices", "<", "10", 10),
    ],
)
def test_parse_expectation(
    expression: str, key: str, op: str, value: str, target: int | None
) -> None:
    parsed = parse_expectation(expression)
    assert (parsed.key, parsed.op, parsed.value, parsed.target) == (key, op, value, target)


@pytest.mark.parametrize(
    "expression",
    ["", "connected", "nonsense=1", "device>=0x1050:0x0407", "connected>=many", "devices>=-1"],
)
def test_malformed_expectations_raise(expression: str) -> None:
    with pytest.raises(ExpectationError):
        parse_expectation(expression)


def test_normalize_usb_id() -> None:
    assert normalize_usb_id("0x1050:0x407") == "0x1050:0x0407"
    assert normalize_usb_id("1050:0407") == "0x1050:0x0407"
    assert normalize_usb_id("0XABCD:0X1") == "0xabcd:0x0001"


# --- matching --------------------------------------------------------------


def test_device_matches_by_id_and_name() -> None:
    device = _device("YubiKey OTP", vendor="Yubico", vendor_id=0x1050, product_id=0x0407)
    assert device_matches(device, "0x1050:0x0407")
    assert device_matches(device, "0x1050:0x0407".replace("0x0407", "0x407"))
    assert device_matches(device, "yubikey")
    assert device_matches(device, "Yubico")
    assert not device_matches(device, "0xdead:0xbeef")
    assert not device_matches(device, "keyboard")


# --- evaluation ------------------------------------------------------------


def test_connected_and_devices_counts_hold() -> None:
    snapshot = _snapshot(devices=(_device(),), ports=(_port(),))
    report = evaluate(
        snapshot, [parse_expectation("connected>=1"), parse_expectation("devices>=1")]
    )
    assert report.passed
    assert report.passed_count == 2
    assert report.failed == ()


def test_a_failing_expectation_is_reported() -> None:
    snapshot = _snapshot(devices=(_device(),), ports=(_port(),))
    report = evaluate(snapshot, [parse_expectation("device=0xdead:0xbeef")])
    assert not report.passed
    assert len(report.failed) == 1
    outcome = report.outcomes[0]
    assert outcome.actual == 0
    assert outcome.detail == "no matching device"
    assert outcome.target is None


def test_port_expectation_is_a_case_insensitive_name_match() -> None:
    snapshot = _snapshot(ports=(_port("USB-C@3"),))
    assert evaluate(snapshot, [parse_expectation("port=usb-c@3")]).passed
    assert not evaluate(snapshot, [parse_expectation("port=USB-C@9")]).passed


def test_warning_zero_is_the_ci_assertion() -> None:
    assert evaluate(_snapshot(), [parse_expectation("warning=0")]).passed
    assert not evaluate(
        _snapshot(warnings=("ioreg failed",)), [parse_expectation("warning=0")]
    ).passed


def test_a_new_device_marks_a_previously_failing_check_as_passed() -> None:
    """The rig scenario: no YubiKey → exit 3, plugged in → exit 0."""
    empty = _snapshot(ports=(_port(connected=False),))
    plugged = _snapshot(devices=(_device("YubiKey"),), ports=(_port(),))
    expectation = [parse_expectation("device=0x1050:0x0407")]
    assert not evaluate(empty, expectation).passed
    assert evaluate(plugged, expectation).passed


# --- output ----------------------------------------------------------------


def test_json_document_shape() -> None:
    report = evaluate(
        _snapshot(), [parse_expectation("connected>=1"), parse_expectation("warning=0")]
    )
    payload = json.loads(check_to_json(report))
    assert payload["kind"] == "check"
    assert payload["passed"] is False
    assert payload["total"] == 2
    assert payload["failed_count"] == 1
    assert payload["expectations"][0]["expression"] == "connected>=1"
    assert payload["expectations"][0]["target"] == 1


def test_render_check_marks_pass_and_fail() -> None:
    passing = evaluate(_snapshot(ports=(_port(),)), [parse_expectation("connected>=1")])
    assert "✓ connected>=1" in render_check(passing)
    failing = evaluate(_snapshot(), [parse_expectation("connected>=1")])
    assert "✗ connected>=1" in render_check(failing)
    assert "0/1 expectation(s) hold — 1 failed" in render_check(failing)


def test_empty_report_passes_vacuously() -> None:
    report = CheckReport()
    assert report.passed
    assert "0/0 expectation(s) hold — ok" in render_check(report)


# --- CLI -------------------------------------------------------------------


def test_cli_check_all_pass(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot(devices=(_device(),), ports=(_port(),)))
    code = cli.main(["check", "--expect", "connected>=1", "--expect", "warning=0", "--no-color"])
    assert code == 0
    assert "2/2 expectation(s) hold — ok" in capsys.readouterr().out


def test_cli_check_failing_exits_three(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot())
    code = cli.main(["check", "--expect", "device=0xdead:0xbeef", "--no-color"])
    assert code == 3
    assert "✗ device=0xdead:0xbeef" in capsys.readouterr().out


def test_cli_check_malformed_exits_two(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot())
    code = cli.main(["check", "--expect", "bogus=1", "--no-color"])
    assert code == 2
    assert "malformed expectation" in capsys.readouterr().err


def test_cli_check_without_expectations_exits_two(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot())
    code = cli.main(["check", "--no-color"])
    assert code == 2
    assert "no --expect" in capsys.readouterr().err


def test_cli_check_json(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: _snapshot(ports=(_port(),)))
    code = cli.main(["check", "--expect", "connected>=1", "--json", "--no-color"])
    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["passed"] is True


def test_check_is_a_parser_command() -> None:
    args = cli.build_parser().parse_args(["check", "--expect", "connected>=1"])
    assert args.view == "check"
    assert args.expect == ["connected>=1"]


def test_expectations_compare_by_value() -> None:
    assert parse_expectation("connected>=1") == parse_expectation("connected>=1")
    assert parse_expectation("connected>=1") != parse_expectation("connected>=2")
