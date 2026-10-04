"""Tests for ``usbscope watch --events`` (attach/detach event stream)."""

from __future__ import annotations

import json
from datetime import datetime

import pytest

from usbscope import cli
from usbscope.events import (
    ATTACHED,
    DETACHED,
    Event,
    device_identity,
    event_dict,
    event_line,
    events_between,
    iter_events,
)
from usbscope.models import Bus, Snapshot, UsbDevice

_WHEN = datetime(2026, 10, 2, 12, 0, 0)
_LATER = datetime(2026, 10, 2, 12, 0, 2)


def _device(
    name: str = "YubiKey",
    *,
    vendor_id: int | None = 0x1050,
    product_id: int | None = 0x0407,
    serial: str | None = None,
    location_id: int | None = 0x0010_0000,
    port: str | None = "USB-C@3",
) -> UsbDevice:
    return UsbDevice(
        name=name,
        vendor_id=vendor_id,
        product_id=product_id,
        serial=serial,
        location_id=location_id,
        port=port,
    )


def _snapshot(*devices: UsbDevice, seen_at: datetime = _WHEN) -> Snapshot:
    buses = (Bus(name="USB 3.1 Bus", devices=devices),) if devices else ()
    return Snapshot(host="mac", os_version="27.0.1", seen_at=seen_at, buses=buses)


def test_device_identity_prefers_location() -> None:
    assert device_identity(_device(location_id=42)) == "loc:42"
    assert device_identity(_device(location_id=None)) == "name:YubiKey"


def test_attach_event_carries_the_device_facts() -> None:
    events = events_between(_snapshot(), _snapshot(_device(serial="ABC"), seen_at=_LATER))
    assert len(events) == 1
    event = events[0]
    assert event.kind == ATTACHED
    assert event.timestamp == _LATER
    assert event.name == "YubiKey"
    assert event.vendor_id == 0x1050
    assert event.product_id == 0x0407
    assert event.serial == "ABC"
    assert event.location_id == 0x0010_0000
    assert event.port == "USB-C@3"


def test_detach_event_is_emitted_for_a_removed_device() -> None:
    events = events_between(_snapshot(_device(), seen_at=_WHEN), _snapshot(seen_at=_LATER))
    assert [event.kind for event in events] == [DETACHED]


def test_detaches_come_before_attaches_and_are_sorted() -> None:
    previous = _snapshot(_device("B", location_id=2), _device("A", location_id=1))
    current = _snapshot(_device("D", location_id=4), _device("C", location_id=3))
    events = events_between(previous, current)
    assert [(event.kind, event.name) for event in events] == [
        (DETACHED, "A"),
        (DETACHED, "B"),
        (ATTACHED, "C"),
        (ATTACHED, "D"),
    ]


def test_an_unchanged_snapshot_produces_no_events() -> None:
    assert events_between(_snapshot(_device()), _snapshot(_device(), seen_at=_LATER)) == []


def test_event_line_is_compact_sorted_json() -> None:
    event = Event(
        timestamp=_WHEN,
        kind=ATTACHED,
        name="YubiKey",
        vendor_id=0x1050,
        product_id=0x0407,
        serial=None,
        location_id=0x0010_0000,
        port="USB-C@3",
    )
    expected = (
        '{"kind":"attached","location_id":1048576,"name":"YubiKey","port":"USB-C@3",'
        '"product_id":1031,"serial":null,"timestamp":"2026-10-02T12:00:00",'
        '"vendor_id":4176}'
    )
    assert event_line(event) == expected
    assert json.loads(event_line(event)) == event_dict(event)


def test_iter_events_skips_the_baseline_read() -> None:
    snapshots = [_snapshot(_device("A", location_id=1)), _snapshot(_device("B", location_id=2))]
    events = list(iter_events(iter(snapshots)))
    assert [(event.kind, event.name) for event in events] == [(DETACHED, "A"), (ATTACHED, "B")]


def test_iter_events_of_a_single_snapshot_is_empty() -> None:
    assert list(iter_events(iter([_snapshot(_device())]))) == []


def test_iter_events_of_no_snapshot_is_empty() -> None:
    assert list(iter_events(iter([]))) == []


# --- CLI -------------------------------------------------------------------


def test_watch_is_a_parser_command() -> None:
    args = cli.build_parser().parse_args(["watch", "--events", "--interval", "1"])
    assert args.view == "watch"
    assert args.events is True
    assert args.interval == 1.0


def test_cli_watch_events_streams_one_line(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    event = Event(_WHEN, ATTACHED, "YubiKey", 0x1050, 0x0407, None, 1, "USB-C@3")
    monkeypatch.setattr(cli, "iter_events", lambda _snapshots: iter([event]))
    assert cli.main(["watch", "--events", "--interval", "0.2", "--no-color"]) == 0
    out = capsys.readouterr().out
    assert out.count("\n") == 1
    assert json.loads(out)["kind"] == "attached"
