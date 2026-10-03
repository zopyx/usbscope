"""Adapter for the battery/charger power telemetry.

Two sources are merged into a :class:`~usbscope.models.Charging`:

* ``system_profiler SPPowerDataType -json`` names the adapter (watt, connected,
  charging state, state of charge) — the numbers System Information shows.
* ``ioreg -r -n AppleSmartBattery -a -l -w0`` carries the live telemetry: what
  comes in from the adapter, what the system draws, what flows into the battery
  and the PD menu the adapter itself advertises.

macOS reports all of this for the machine as a whole. A port controller never
publishes a measured per-port draw — only the negotiated contract, which the
``ioreg`` adapter reads.
"""

from __future__ import annotations

import json
import plistlib
from collections.abc import Callable
from typing import Any

from ..models import Charging
from .shell import CommandResult, run_command, system_binary

__all__ = ["ChargingSource"]

Runner = Callable[[list[str]], CommandResult]

SYSTEM_PROFILER = system_binary(
    "system_profiler", "/usr/sbin/system_profiler", "/usr/bin/system_profiler"
)
IOREG = system_binary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")

BATTERY_CLASS = "AppleSmartBattery"
_ADAPTER_ENTRY = "sppower_ac_charger_information"
_BATTERY_ENTRY = "spbattery_information"


def _int(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    try:
        return int(str(value).strip(), 0)
    except ValueError:
        return None


def _bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"yes", "true", "y"}:
            return True
        if lowered in {"no", "false", "n"}:
            return False
    return None


def _first(*values: Any) -> Any:
    """The first value that is not ``None``."""
    for value in values:
        if value is not None:
            return value
    return None


def _minutes(value: Any) -> int | None:
    """A minute value, with the ``0``/``65535`` placeholders of macOS as unknown."""
    number = _int(value)
    if number is None or number <= 0 or number >= 65535:
        return None
    return number


def _mw_from_watts(value: Any) -> int | None:
    number = _int(value)
    return None if number is None else number * 1000


def _battery(value: Any) -> dict[str, Any] | None:
    """Find the ``AppleSmartBattery`` node inside a parsed ioreg plist."""
    if isinstance(value, dict):
        if value.get("IOObjectClass") == BATTERY_CLASS or "InstantAmperage" in value:
            return value
        for child in value.values():
            found = _battery(child)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _battery(child)
            if found is not None:
                return found
    return None


def _group(node: dict[str, Any], key: str) -> dict[str, Any]:
    value = node.get(key)
    return value if isinstance(value, dict) else {}


def _adapter(node: dict[str, Any]) -> dict[str, Any]:
    """The adapter row macOS reports, whichever of its two keys is present."""
    for key in ("AdapterDetails", "AppleRawAdapterDetails"):
        value = node.get(key)
        entries = value if isinstance(value, list) else [value]
        for entry in entries:
            if isinstance(entry, dict):
                return entry
    return {}


class ChargingSource:
    """Reads the live power and charging telemetry of the machine."""

    def __init__(self, runner: Runner | None = None) -> None:
        self._run = runner or run_command

    def _power_report(self) -> tuple[dict[str, Any], dict[str, Any], str | None]:
        """Return the adapter entry, the charge info and an optional warning."""
        result = self._run([SYSTEM_PROFILER, "SPPowerDataType", "-json"])
        if not result.ok:
            return {}, {}, result.error or "system_profiler SPPowerDataType failed"
        try:
            payload = json.loads(result.stdout.decode("utf-8", "replace"))
        except ValueError:
            return {}, {}, "system_profiler SPPowerDataType returned unparsable output"
        entries = payload.get("SPPowerDataType") or []
        if isinstance(entries, dict):
            entries = [entries]
        adapter: dict[str, Any] = {}
        charge: dict[str, Any] = {}
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            if entry.get("_name") == _ADAPTER_ENTRY:
                adapter = entry
            elif entry.get("_name") == _BATTERY_ENTRY:
                info = entry.get("sppower_battery_charge_info")
                charge = info if isinstance(info, dict) else {}
        return adapter, charge, None

    def _battery_node(self) -> tuple[dict[str, Any] | None, str | None]:
        result = self._run([IOREG, "-r", "-n", BATTERY_CLASS, "-a", "-l", "-w0"])
        if not result.ok:
            return None, result.error or "ioreg failed"
        if not result.stdout.strip():
            return None, None  # a machine without this class: nothing to report
        try:
            tree = plistlib.loads(result.stdout)
        except Exception:
            return None, "ioreg returned unparsable output"
        return _battery(tree), None

    def charging(self) -> tuple[Charging | None, tuple[str, ...]]:
        """Return the live charging telemetry plus any non-fatal warnings.

        A desktop without a battery reports neither source and stays silent:
        that is a normal state, not a problem.
        """
        warnings: list[str] = []
        adapter_entry, charge, power_warning = self._power_report()
        if power_warning:
            warnings.append(power_warning)
        node, battery_warning = self._battery_node()
        if battery_warning:
            warnings.append(battery_warning)
        if node is None and not adapter_entry and not charge:
            return None, tuple(dict.fromkeys(warnings))

        node = node or {}
        telemetry = _group(node, "PowerTelemetryData")
        charger_data = _group(node, "ChargerData")
        adapter = _adapter(node)
        charging = Charging(
            connected=_bool(
                _first(
                    adapter_entry.get("sppower_battery_charger_connected"),
                    node.get("ExternalConnected"),
                )
            ),
            charging=_bool(
                _first(
                    charge.get("sppower_battery_is_charging"),
                    adapter_entry.get("sppower_battery_is_charging"),
                    node.get("IsCharging"),
                    charger_data.get("IsCharging"),
                )
            ),
            fully_charged=_bool(
                _first(
                    charge.get("sppower_battery_fully_charged"),
                    node.get("FullyCharged"),
                )
            ),
            state_of_charge=_int(charge.get("sppower_battery_state_of_charge")),
            time_remaining_minutes=_minutes(node.get("TimeRemaining")),
            system_power_in_mw=_int(telemetry.get("SystemPowerIn")),
            system_voltage_in_mv=_int(telemetry.get("SystemVoltageIn")),
            system_current_in_ma=_int(telemetry.get("SystemCurrentIn")),
            system_load_mw=_int(telemetry.get("SystemLoad")),
            battery_power_mw=_int(telemetry.get("BatteryPower")),
            battery_voltage_mv=_int(node.get("Voltage")),
            battery_current_ma=_int(_first(node.get("InstantAmperage"), node.get("Amperage"))),
            adapter_power_mw=_first(
                _mw_from_watts(adapter.get("Watts")),
                _mw_from_watts(adapter_entry.get("sppower_ac_charger_watts")),
            ),
            adapter_voltage_mv=_int(adapter.get("AdapterVoltage")),
            adapter_current_ma=_int(adapter.get("Current")),
            adapter_efficiency_loss_mw=_int(telemetry.get("AdapterEfficiencyLoss")),
            not_charging_reason=_int(charger_data.get("NotChargingReason")),
            slow_charging_reason=_int(charger_data.get("SlowChargingReason")),
            thermally_limited_seconds=_int(charger_data.get("TimeChargingThermallyLimited")),
        )
        unique = tuple(dict.fromkeys(warnings))  # both commands may fail alike
        if charging == Charging():
            return None, unique
        return charging, unique
