"""Tests for the shared power formatting."""

from __future__ import annotations

from usbscope.format import (
    amps,
    charger_flags,
    charging_state,
    charging_summary,
    power_line,
    volts,
    watts,
)
from usbscope.models import Charging


def test_units_are_rendered_from_the_raw_values() -> None:
    assert watts(None) is None
    assert watts(27575) == "27.6 W"
    assert watts(70000, compact=True) == "70 W"
    assert volts(19478) == "19.5 V"
    assert volts(20000, compact=True) == "20 V"
    assert amps(1417) == "1.42 A"
    assert amps(3500, compact=True) == "3.5 A"


def test_power_line_skips_what_is_unknown() -> None:
    assert power_line(27575, None, 1417) == "27.6 W · 1.42 A"
    assert power_line(None, None, None) is None


def test_charging_state_and_summary() -> None:
    charging = Charging(
        connected=True,
        charging=True,
        state_of_charge=42,
        time_remaining_minutes=17,
        system_power_in_mw=35958,
        battery_power_mw=21773,
        system_load_mw=14185,
    )
    assert charging_state(charging) == "charging · 42 % · 17 min to full"
    assert charging_summary(charging) == "36.0 W in · 21.8 W battery · 14.2 W system"


def test_charging_state_of_every_situation() -> None:
    # a full battery gets no time estimate, macOS reports none at that point
    full = Charging(
        connected=True, fully_charged=True, state_of_charge=100, time_remaining_minutes=14
    )
    assert charging_state(full) == "fully charged · 100 %"
    # plugged in but the battery is not taking current
    idle = Charging(connected=True, charging=False, fully_charged=False, state_of_charge=80)
    assert charging_state(idle) == "plugged in, not charging · 80 %"
    on_battery = Charging(connected=False, state_of_charge=8, time_remaining_minutes=95)
    assert charging_state(on_battery) == "on battery · 8 % · 95 min left"
    assert charging_state(Charging(state_of_charge=50)) == "50 %"
    assert charging_state(Charging()) is None
    assert charging_summary(Charging()) is None


def test_charger_flags_are_only_reported_when_set() -> None:
    assert charger_flags(Charging()) is None
    assert charger_flags(Charging(slow_charging_reason=2)) == "slow charging: 2"
    assert (
        charger_flags(Charging(not_charging_reason=3, thermally_limited_seconds=90))
        == "not charging: 3, thermally limited 90 s"
    )
