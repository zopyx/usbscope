"""Tests for the pure power history: bounded ring + power timeline."""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest

from usbscope.history import DEFAULT_CAPACITY, PowerHistory, PowerPoint, power_point
from usbscope.models import Charging, Snapshot

_T0 = datetime(2026, 10, 3, 17, 0, 0)


def _charging(
    *, watts_mw: int | None = 27575, soc: int | None = 100, charging: bool | None = True
) -> Charging:
    return Charging(system_power_in_mw=watts_mw, state_of_charge=soc, charging=charging)


def _at(minutes: int) -> datetime:
    return _T0 + timedelta(minutes=minutes)


def test_default_capacity() -> None:
    assert DEFAULT_CAPACITY == 240
    assert PowerHistory().capacity == DEFAULT_CAPACITY


def test_capacity_must_be_positive() -> None:
    with pytest.raises(ValueError):
        PowerHistory(0)
    with pytest.raises(ValueError):
        PowerHistory(-1)


def test_power_point_maps_the_live_system_power() -> None:
    point = power_point(_charging(watts_mw=27575, soc=100, charging=True), _at(0))
    assert point == PowerPoint(seen_at=_at(0), watts=27.575, state_of_charge=100, charging=True)
    assert point.has_power


def test_power_point_of_a_missing_sample_is_a_gap() -> None:
    point = power_point(None, _at(1))
    assert point == PowerPoint(seen_at=_at(1))
    assert point.watts is None
    assert point.state_of_charge is None
    assert point.charging is None
    assert not point.has_power


def test_power_point_keeps_an_unknown_watt_as_none() -> None:
    point = power_point(_charging(watts_mw=None, soc=42, charging=False), _at(2))
    assert point.watts is None
    assert point.state_of_charge == 42
    assert point.charging is False


def test_record_appends_and_returns_the_point() -> None:
    history = PowerHistory(capacity=4)
    assert not history
    point = history.record(_charging(), seen_at=_at(0))
    assert point == history.latest
    assert len(history) == 1
    assert history


def test_ring_drops_the_oldest_beyond_capacity() -> None:
    history = PowerHistory(capacity=2)
    history.record(_charging(watts_mw=1000), seen_at=_at(0))
    history.record(_charging(watts_mw=2000), seen_at=_at(1))
    history.record(_charging(watts_mw=3000), seen_at=_at(2))

    assert len(history) == 2
    assert [point.seen_at for point in history.points] == [_at(1), _at(2)]
    assert history.latest is not None and history.latest.watts == 3.0


def test_timeline_is_oldest_first_and_keeps_the_gaps() -> None:
    history = PowerHistory(capacity=8)
    history.record(None, seen_at=_at(0))
    history.record(_charging(watts_mw=5000), seen_at=_at(1))

    timeline = history.timeline()
    assert timeline == history.points
    assert [point.seen_at for point in timeline] == [_at(0), _at(1)]
    assert timeline[0].watts is None
    assert timeline[1].watts == 5.0


def test_watts_timeline_drops_the_gaps() -> None:
    history = PowerHistory(capacity=8)
    history.record(None, seen_at=_at(0))
    history.record(_charging(watts_mw=5000), seen_at=_at(1))
    history.record(_charging(watts_mw=None), seen_at=_at(2))

    assert history.watts_timeline() == ((_at(1), 5.0),)


def test_record_many_keeps_the_order() -> None:
    history = PowerHistory(capacity=8)
    history.record_many(
        [
            (_at(0), _charging(watts_mw=1000)),
            (_at(1), None),
            (_at(2), _charging(watts_mw=3000)),
        ]
    )
    assert len(history) == 3
    assert [point.watts for point in history.points] == [1.0, None, 3.0]


def test_clear_and_latest_of_an_empty_history() -> None:
    history = PowerHistory(capacity=4)
    history.record(_charging(), seen_at=_at(0))
    history.clear()
    assert len(history) == 0
    assert history.latest is None
    assert not history


def test_timeline_over_the_captured_telemetry(snapshot: Snapshot) -> None:
    """The real captured charging data maps onto the documented timeline point."""
    charging = snapshot.charging
    assert charging is not None  # the fixture machine is charging

    history = PowerHistory(capacity=8)
    history.record(charging, seen_at=snapshot.seen_at)

    point = history.latest
    assert point is not None
    assert point.seen_at == snapshot.seen_at
    assert point.watts == 27.575
    assert point.state_of_charge == 100
    assert point.charging is True
