"""Human readable formatting of the raw power numbers.

Both frontends (the Rich CLI and the AppKit app) must print the same strings, so
they are built here instead of being duplicated in ``render`` and ``viewmodel``.
The domain model keeps the raw OS values (mV, mA, mW) untouched.
"""

from __future__ import annotations

from .models import Charging

__all__ = [
    "amps",
    "charger_flags",
    "charging_state",
    "charging_summary",
    "power_line",
    "volts",
    "watts",
]


def watts(mw: int | None, *, compact: bool = False) -> str | None:
    """Milliwatts as watt: ``35.9 W``, or ``36 W`` when asked compactly."""
    if mw is None:
        return None
    return f"{mw / 1000:g} W" if compact else f"{mw / 1000:.1f} W"


def volts(mv: int | None, *, compact: bool = False) -> str | None:
    """Millivolts as volt: ``19.4 V``, or ``20 V`` when asked compactly."""
    if mv is None:
        return None
    return f"{mv / 1000:g} V" if compact else f"{mv / 1000:.1f} V"


def amps(ma: int | None, *, compact: bool = False) -> str | None:
    """Milliamps as ampere: ``1.86 A``, or ``3.5 A`` when asked compactly."""
    if ma is None:
        return None
    return f"{ma / 1000:g} A" if compact else f"{ma / 1000:.2f} A"


def power_line(
    power_mw: int | None,
    voltage_mv: int | None,
    current_ma: int | None,
    *,
    compact: bool = False,
) -> str | None:
    """``36.0 W · 19.4 V · 1.86 A`` — only the parts that are known."""
    parts = [
        watts(power_mw, compact=compact),
        volts(voltage_mv, compact=compact),
        amps(current_ma, compact=compact),
    ]
    return " · ".join(part for part in parts if part) or None


def charger_flags(charging: Charging) -> str | None:
    """The charger problems macOS would act on (``0`` means it sees none)."""
    flags = [
        f"not charging: {charging.not_charging_reason}" if charging.not_charging_reason else None,
        f"slow charging: {charging.slow_charging_reason}"
        if charging.slow_charging_reason
        else None,
        f"thermally limited {charging.thermally_limited_seconds} s"
        if charging.thermally_limited_seconds
        else None,
    ]
    return ", ".join(flag for flag in flags if flag) or None


def charging_state(charging: Charging) -> str | None:
    """``charging · 42 % · 17 min to full`` — state, charge and remaining time."""
    if charging.charging:
        state = "charging"
    elif charging.fully_charged:
        state = "fully charged"
    elif charging.connected:
        state = "plugged in, not charging"
    elif charging.connected is False:
        state = "on battery"
    else:
        state = None
    parts = [state] if state else []
    if charging.state_of_charge is not None:
        parts.append(f"{charging.state_of_charge} %")
    if charging.time_remaining_minutes and not charging.fully_charged:
        # macOS reports one value for both directions and none when it is full
        parts.append(
            f"{charging.time_remaining_minutes} min {'to full' if charging.charging else 'left'}"
        )
    return " · ".join(parts) or None


def charging_summary(charging: Charging) -> str | None:
    """``35.9 W in · 21.8 W battery · 14.2 W system`` — only what is known."""
    parts = [
        part
        for part in (
            f"{watts(charging.system_power_in_mw)} in"
            if charging.system_power_in_mw is not None
            else None,
            f"{watts(charging.battery_power_mw)} battery"
            if charging.battery_power_mw is not None
            else None,
            f"{watts(charging.system_load_mw)} system"
            if charging.system_load_mw is not None
            else None,
        )
        if part
    ]
    return " · ".join(parts) or None
