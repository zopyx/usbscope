"""Aggregation service: turn the raw OS reports into one :class:`Snapshot`."""

from __future__ import annotations

import platform
from collections.abc import Callable, Iterable
from dataclasses import replace
from datetime import datetime

from .models import Bus, Port, Snapshot, UsbDevice
from .sources import IoregSource, SystemProfiler

__all__ = ["collect"]

Clock = Callable[[], datetime]

_ORPHAN_BUS = "Port controller only (no bus entry)"


def _merge(primary: UsbDevice, other: UsbDevice | None) -> UsbDevice:
    """Fill the gaps of ``primary`` with values reported by ``other``."""
    if other is None:
        return primary
    filled = {
        field: getattr(primary, field)
        if getattr(primary, field) is not None
        else getattr(other, field)
        for field in (
            "vendor",
            "serial",
            "version",
            "connection",
            "bus",
            "speed_mbps",
            "speed_text",
            "port",
            "port_type",
            "transport",
            "generation",
            "restricted",
        )
    }
    return replace(primary, **filled)


def _index(devices: Iterable[UsbDevice]) -> dict[int, UsbDevice]:
    return {device.location_id: device for device in devices if device.location_id}


def collect(
    *,
    profiler: SystemProfiler | None = None,
    ioreg: IoregSource | None = None,
    clock: Clock = datetime.now,
    os_version: str | None = None,
    host: str | None = None,
) -> Snapshot:
    """Read every source and merge the results into a single snapshot.

    Broken or missing sources never abort the collection: their message is kept
    in ``Snapshot.warnings`` so the UI can show it instead of a traceback.

    ``os_version`` and ``host`` default to this machine. Tests inject them together
    with the captured fixtures, otherwise the snapshot of a *captured* machine would
    carry the macOS version of whatever host the suite happens to run on.
    """
    profiler = profiler or SystemProfiler()
    ioreg = ioreg or IoregSource()
    warnings: list[str] = []
    ports, port_warnings = ioreg.ports()
    warnings.extend(port_warnings)
    buses, bus_warnings = profiler.usb_buses()
    warnings.extend(bus_warnings)
    thunderbolt, tb_warnings = profiler.thunderbolt()
    warnings.extend(tb_warnings)
    hardware, hardware_warnings = profiler.hardware()
    warnings.extend(hardware_warnings)

    bus_index = _index(device for bus in buses for device in bus.devices)
    port_index = _index(device for port in ports for device in port.devices)

    merged_buses: list[Bus] = [
        replace(
            bus,
            devices=tuple(
                _merge(device, port_index.get(device.location_id or -1)) for device in bus.devices
            ),
        )
        for bus in buses
    ]
    merged_ports: tuple[Port, ...] = tuple(
        replace(
            port,
            devices=tuple(
                _merge(device, bus_index.get(device.location_id or -1)) for device in port.devices
            ),
        )
        for port in ports
    )
    orphans = tuple(device for key, device in port_index.items() if key not in bus_index)
    if orphans:
        merged_buses.append(Bus(name=_ORPHAN_BUS, driver="ioreg", devices=orphans))

    return Snapshot(
        host=host or platform.node() or "this Mac",
        os_version=os_version or platform.mac_ver()[0] or platform.platform(),
        seen_at=clock(),
        model=hardware.get("model"),
        chip=hardware.get("chip"),
        ports=merged_ports,
        buses=tuple(merged_buses),
        thunderbolt=thunderbolt,
        warnings=tuple(warnings),
    )
