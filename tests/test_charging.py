"""Tests for the battery/charger telemetry adapter against a real capture."""

from __future__ import annotations

import plistlib

from usbscope.sources import ChargingSource
from usbscope.sources.shell import CommandResult


def test_charging_from_a_real_capture(charging: ChargingSource) -> None:
    """System Information names the adapter, the SMC reports the live numbers."""
    data, warnings = charging.charging()
    assert warnings == ()
    assert data is not None
    assert data.connected is True
    assert data.charging is True
    assert data.fully_charged is True
    assert data.state_of_charge == 100
    assert data.time_remaining_minutes == 14
    assert data.system_power_in_mw == 27575
    assert data.system_voltage_in_mv == 19478
    assert data.system_current_in_ma == 1417
    assert data.system_load_mw == 16084
    assert data.battery_power_mw == 11491
    assert data.battery_voltage_mv == 12955
    assert data.battery_current_ma == 887
    assert data.adapter_power_mw == 70000
    assert data.adapter_voltage_mv == 20000
    assert data.adapter_current_ma == 3500
    assert data.adapter_efficiency_loss_mw == 679
    assert data.not_charging_reason == 0
    assert data.slow_charging_reason == 0
    assert data.thermally_limited_seconds == 0


def test_a_desktop_without_a_battery_reports_nothing() -> None:
    """No battery class, no charge info: a normal state, not a warning."""
    payload = b'{"SPPowerDataType": [{"_name": "sppower_information"}]}'

    def runner(argv: list[str]) -> CommandResult:
        if "SPPowerDataType" in argv:
            return CommandResult(tuple(argv), 0, payload)
        return CommandResult(tuple(argv), 0, b"")

    data, warnings = ChargingSource(runner=runner).charging()
    assert data is None
    assert warnings == ()


def test_the_charge_info_alone_is_enough() -> None:
    """A machine that reports only the adapter still yields a result."""
    payload = (
        b'{"SPPowerDataType": [{"_name": "sppower_ac_charger_information",'
        b' "sppower_ac_charger_watts": "96",'
        b' "sppower_battery_charger_connected": "TRUE",'
        b' "sppower_battery_is_charging": "FALSE"}]}'
    )

    def runner(argv: list[str]) -> CommandResult:
        if "SPPowerDataType" in argv:
            return CommandResult(tuple(argv), 0, payload)
        return CommandResult(tuple(argv), 0, b"")

    data, warnings = ChargingSource(runner=runner).charging()
    assert warnings == ()
    assert data is not None
    assert data.connected is True
    assert data.charging is False
    assert data.adapter_power_mw == 96000
    assert data.system_power_in_mw is None


def test_placeholder_minutes_are_unknown() -> None:
    """``0``/``65535`` mean "still estimating", not "now"."""
    charge = (
        b'{"SPPowerDataType": [{"_name": "spbattery_information",'
        b' "sppower_battery_charge_info": {"sppower_battery_is_charging": "FALSE",'
        b' "sppower_battery_state_of_charge": 40}}]}'
    )
    node = plistlib.dumps(
        [
            {
                "IOObjectClass": "AppleSmartBattery",
                "TimeRemaining": 65535,
                "IsCharging": False,
                "ExternalConnected": True,
            }
        ]
    )

    def runner(argv: list[str]) -> CommandResult:
        if "SPPowerDataType" in argv:
            return CommandResult(tuple(argv), 0, charge)
        return CommandResult(tuple(argv), 0, node)

    data, _warnings = ChargingSource(runner=runner).charging()
    assert data is not None
    assert data.time_remaining_minutes is None
    assert data.charging is False
    assert data.connected is True
    assert data.state_of_charge == 40


def test_failing_commands_are_reported_once() -> None:
    def runner(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 1, error="system_profiler not found")

    data, warnings = ChargingSource(runner=runner).charging()
    assert data is None
    assert warnings == ("system_profiler not found",)  # not repeated per command


def test_unparsable_output_is_reported() -> None:
    def runner(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 0, b"not a payload")

    data, warnings = ChargingSource(runner=runner).charging()
    assert data is None
    assert len(warnings) == 2  # the JSON report and the plist
