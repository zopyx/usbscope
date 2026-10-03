"""Tests for the security posture analyser (``usbscope.security``)."""

from __future__ import annotations

import json
from datetime import datetime

import pytest
from rich.console import Console

from usbscope import cli
from usbscope.models import Bus, Port, Snapshot, Transport, UsbDevice
from usbscope.render import render_security
from usbscope.security import Finding, FindingSeverity, SecurityReport, analyse
from usbscope.serialize import security_to_dict, security_to_json
from usbscope.sources.storage import StorageDevice

_WHEN = datetime(2026, 10, 2, 12, 0, 0)


def _device(
    name: str = "Gadget",
    *,
    device_class: int | None = None,
    subclass: int | None = None,
    protocol: int | None = None,
    serial: str | None = None,
    restricted: bool | None = None,
    location_id: int | None = 1,
) -> UsbDevice:
    return UsbDevice(
        name=name,
        device_class=device_class,
        device_subclass=subclass,
        device_protocol=protocol,
        serial=serial,
        restricted=restricted,
        location_id=location_id,
    )


def _port(
    name: str = "USB-C@1",
    *,
    connected: bool = False,
    authorization: str | None = None,
    transports: tuple[Transport, ...] = (),
    devices: tuple[UsbDevice, ...] = (),
) -> Port:
    return Port(
        description=f"Port-{name}",
        kind="USB-C",
        number=1,
        connected=connected,
        authorization=authorization,
        transports=transports,
        devices=devices,
    )


def _snapshot(*, devices: tuple[UsbDevice, ...] = (), ports: tuple[Port, ...] = ()) -> Snapshot:
    buses = (Bus(name="USB 3.1 Bus", devices=devices),) if devices else ()
    return Snapshot(host="mac", os_version="27.0.1", seen_at=_WHEN, ports=ports, buses=buses)


def _rules(report: SecurityReport) -> list[str]:
    return [finding.rule for finding in report.findings]


def _find(report: SecurityReport, rule: str) -> list[Finding]:
    return [finding for finding in report.findings if finding.rule == rule]


def test_mass_storage_device_is_a_warning() -> None:
    report = analyse(_snapshot(devices=(_device("Stick", device_class=0x08),)))
    finding = _find(report, "mass-storage")[0]
    assert finding.severity is FindingSeverity.WARNING
    assert finding.subject == "Stick"
    assert "class 8" in finding.detail


def test_hid_without_serial_is_attention() -> None:
    report = analyse(_snapshot(devices=(_device("Keyboard", device_class=0x03),)))
    finding = _find(report, "hid-without-serial")[0]
    assert finding.severity is FindingSeverity.ATTENTION
    assert "serial number" in finding.detail


def test_hid_with_a_serial_is_not_flagged() -> None:
    device = _device("Keyboard", device_class=0x03, serial="ABC123")
    report = analyse(_snapshot(devices=(device,)))
    assert _find(report, "hid-without-serial") == []


def test_composite_class_zero_is_only_an_info() -> None:
    """A class of 0 means per-interface; the interfaces are not exposed."""
    report = analyse(_snapshot(devices=(_device("Hub-ish", device_class=0x00),)))
    finding = _find(report, "composite-per-interface")[0]
    assert finding.severity is FindingSeverity.INFO
    assert "cannot be confirmed" in finding.detail
    assert "HID and mass storage" in finding.detail


def test_iad_composite_is_reported_as_info() -> None:
    device = _device("Combo", device_class=0xEF, subclass=0x02, protocol=0x01)
    report = analyse(_snapshot(devices=(device,)))
    assert _rules(report) == ["composite-iad"]


def test_restricted_device_is_attention() -> None:
    report = analyse(_snapshot(devices=(_device("Odd", restricted=True),)))
    finding = _find(report, "restricted-by-macos")[0]
    assert finding.severity is FindingSeverity.ATTENTION


def test_device_without_a_class_is_not_flagged() -> None:
    report = analyse(_snapshot(devices=(_device("Anonymous"),)))
    assert report.is_empty


def test_nonstandard_authorization_is_attention() -> None:
    report = analyse(_snapshot(ports=(_port(authorization="Denied"),)))
    finding = _find(report, "authorization")[0]
    assert finding.severity is FindingSeverity.ATTENTION
    assert "Denied" in finding.detail


def test_standard_authorizations_are_not_flagged() -> None:
    for value in ("Not Required", "No Action", None):
        report = analyse(_snapshot(ports=(_port(authorization=value),)))
        assert _find(report, "authorization") == []


def test_an_active_restricted_transport_is_attention() -> None:
    active = Transport(kind="USB3", active=True, restricted=True)
    report = analyse(_snapshot(ports=(_port(transports=(active,)),)))
    assert len(_find(report, "restricted-transport")) == 1


def test_an_idle_restricted_transport_is_not_flagged() -> None:
    idle = Transport(kind="USB3", active=False, restricted=True)
    report = analyse(_snapshot(ports=(_port(transports=(idle,)),)))
    assert _find(report, "restricted-transport") == []


def test_a_device_without_an_active_usb_transport_is_attention() -> None:
    port = _port(
        connected=True,
        transports=(Transport(kind="CC", active=True),),
        devices=(_device("Ghost", device_class=0x00),),
    )
    report = analyse(_snapshot(ports=(port,)))
    assert len(_find(report, "no-usb-data")) == 1


def test_an_active_usb_transport_silences_the_no_data_rule() -> None:
    port = _port(
        connected=True,
        transports=(Transport(kind="USB2", active=True),),
        devices=(_device("Real", device_class=0x00),),
    )
    report = analyse(_snapshot(ports=(port,)))
    assert _find(report, "no-usb-data") == []


def test_a_port_with_hid_and_storage_is_a_warning() -> None:
    port = _port(
        devices=(
            _device("Keyboard", device_class=0x03, location_id=2),
            _device("Stick", device_class=0x08, location_id=3),
        )
    )
    report = analyse(_snapshot(ports=(port,)))
    finding = _find(report, "hid-and-storage-on-port")[0]
    assert finding.severity is FindingSeverity.WARNING
    assert finding.subject == "USB-C@1"


def test_findings_are_sorted_most_severe_first() -> None:
    report = analyse(
        _snapshot(
            devices=(
                _device("Stick", device_class=0x08, location_id=1),
                _device("Keyboard", device_class=0x03, location_id=2),
                _device("Combo", device_class=0x00, location_id=3),
            )
        )
    )
    assert [finding.severity for finding in report.findings] == [
        FindingSeverity.WARNING,
        FindingSeverity.ATTENTION,
        FindingSeverity.INFO,
    ]
    assert _rules(report) == ["mass-storage", "hid-without-serial", "composite-per-interface"]


def test_counts_are_stable() -> None:
    report = analyse(
        _snapshot(
            devices=(
                _device("Stick", device_class=0x08, location_id=1),
                _device("Combo", device_class=0x00, location_id=2),
            )
        )
    )
    assert report.counts == {"info": 1, "attention": 0, "warning": 1, "total": 2}
    assert report.count(FindingSeverity.WARNING) == 1


def test_an_empty_snapshot_has_no_findings() -> None:
    report = analyse(_snapshot())
    assert report.is_empty
    assert report.counts == {"info": 0, "attention": 0, "warning": 0, "total": 0}


def test_the_fixture_snapshot_reports_the_yubikey_as_per_interface(snapshot: Snapshot) -> None:
    """The captured YubiKey declares class 0 — an info, never a guessed HID/storage mix."""
    report = analyse(snapshot)
    composites = _find(report, "composite-per-interface")
    assert len(composites) == 1
    assert composites[0].subject.startswith("Yubico YubiKey")


def test_the_analysis_does_not_mutate_the_snapshot(snapshot: Snapshot) -> None:
    before = snapshot
    analyse(snapshot)
    assert snapshot == before


# --- CLI, rendering and JSON ------------------------------------------------


class _FakeStorage:
    """A storage source that reports nothing, so the CLI tests stay offline."""

    def inventory(self) -> tuple[tuple[StorageDevice, ...], tuple[str, ...]]:
        return ((), ())


def test_cli_accepts_the_security_view() -> None:
    assert cli.build_parser().parse_args(["security"]).view == "security"


def test_cli_security_json_is_its_own_document(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], snapshot: Snapshot
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: snapshot)
    monkeypatch.setattr(cli, "StorageSource", _FakeStorage)
    assert cli.main(["security", "--json", "--no-color"]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["kind"] == "security"
    assert payload["schema_version"] == 1
    assert payload["counts"]["total"] == len(payload["findings"]) == 1
    assert payload["findings"][0]["rule"] == "composite-per-interface"
    assert payload["storage"] == []


def test_cli_security_view_renders_the_findings(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], snapshot: Snapshot
) -> None:
    monkeypatch.setattr(cli, "collect", lambda: snapshot)
    monkeypatch.setattr(cli, "StorageSource", _FakeStorage)
    assert cli.main(["security", "--no-color"]) == 0
    out = capsys.readouterr().out
    assert "Security posture" in out
    assert "composite-per-interface" in out
    assert "no USB mass storage attached" in out


def test_render_security_prints_the_storage_inventory(snapshot: Snapshot) -> None:
    console = Console(
        width=200, record=True, force_terminal=False, color_system=None, highlight=False
    )
    device = StorageDevice(
        identifier="disk4",
        name="STICK",
        bus_protocol="USB",
        capacity_bytes=32_000_000_000,
        read_only=False,
        mount_point="/Volumes/STICK",
    )
    render_security(snapshot, (device,), console)
    out = console.export_text()
    assert "USB mass storage" in out
    assert "disk4" in out
    assert "32.0 GB" in out
    assert "read/write" in out


def test_security_json_serialiser_shape() -> None:
    report = analyse(_snapshot(devices=(_device("Stick", device_class=0x08),)))
    when = datetime(2026, 10, 2, 12, 0, 0)
    payload = security_to_dict(report, (), generated_at=when)
    assert payload["kind"] == "security"
    assert payload["generated_at"] == "2026-10-02T12:00:00"
    assert payload["counts"]["warning"] == 1
    text = security_to_json(report, (), generated_at=when)
    assert json.loads(text)["findings"][0]["rule"] == "mass-storage"
