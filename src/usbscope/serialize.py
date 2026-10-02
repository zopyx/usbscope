"""Machine readable representation of a snapshot (``usbscope --json``)."""

from __future__ import annotations

import json
from typing import Any

from .models import Bus, Cable, Port, Snapshot, ThunderboltPort, Transport, UsbDevice

__all__ = ["snapshot_to_dict", "snapshot_to_json"]

SCHEMA_VERSION = 1


def _device(device: UsbDevice) -> dict[str, Any]:
    return {
        "name": device.name,
        "vendor": device.vendor,
        "vendor_id": device.vendor_id,
        "product_id": device.product_id,
        "id": device.id_string,
        "serial": device.serial,
        "location_id": device.location_id,
        "speed_mbps": device.speed_mbps,
        "mode": device.mode.value,
        "mode_label": device.mode.label,
        "connection": device.connection,
        "version": device.version,
        "bus": device.bus,
        "port": device.port,
        "port_type": device.port_type,
        "transport": device.transport,
        "generation": device.generation,
        "restricted": device.restricted,
        "source": device.source,
    }


def _cable(cable: Cable) -> dict[str, Any]:
    return {
        "attached": cable.attached,
        "kind": cable.kind,
        "emarker": cable.emarker,
        "active": cable.active,
        "optical": cable.optical,
        "authentication": cable.authentication,
        "hash_status": cable.hash_status,
        "pd_spec_revision": cable.pd_spec_revision,
    }


def _transport(transport: Transport) -> dict[str, Any]:
    return {
        "kind": transport.kind,
        "active": transport.active,
        "rate": transport.rate_text,
        "speed_mbps": transport.speed_mbps,
        "mode": transport.mode.value,
        "generation": transport.generation,
        "signaling": transport.signaling,
        "data_role": transport.data_role,
        "lanes": transport.lanes,
        "restricted": transport.restricted,
        "trm_state": transport.trm_state,
        "trm_profile": transport.trm_profile,
        "hash_status": transport.hash_status,
    }


def _port(port: Port) -> dict[str, Any]:
    return {
        "description": port.description,
        "name": port.name,
        "kind": port.kind,
        "number": port.number,
        "connected": port.connected,
        "mode": port.mode.value,
        "mode_label": port.mode.label,
        "connect_type": port.connect_type,
        "super_speed_active": port.super_speed_active,
        "plug_orientation": port.plug_orientation,
        "displayport_pin_assignment": port.displayport_pin_assignment,
        "liquid_detected": port.liquid_detected,
        "authorization": port.authorization,
        "firmware": port.firmware,
        "power_in": list(port.power_in),
        "cable": _cable(port.cable),
        "transports": [_transport(item) for item in port.transports],
        "devices": [_device(item) for item in port.devices],
    }


def _bus(bus: Bus) -> dict[str, Any]:
    return {
        "name": bus.name,
        "driver": bus.driver,
        "location_id": bus.location_id,
        "connection": bus.connection,
        "protocol": bus.protocol,
        "devices": [_device(item) for item in bus.devices],
    }


def _thunderbolt(port: ThunderboltPort) -> dict[str, Any]:
    return {
        "bus": port.bus,
        "receptacle": port.receptacle,
        "status": port.status,
        "speed": port.speed,
        "connected": port.connected,
        "device": port.device,
        "vendor": port.vendor,
    }


def snapshot_to_dict(snapshot: Snapshot) -> dict[str, Any]:
    """Serialise a snapshot into plain JSON compatible types."""
    return {
        "schema_version": SCHEMA_VERSION,
        "host": snapshot.host,
        "os_version": snapshot.os_version,
        "model": snapshot.model,
        "chip": snapshot.chip,
        "seen_at": snapshot.seen_at.isoformat(timespec="seconds"),
        "summary": {
            "ports": len(snapshot.ports),
            "connected_ports": len(snapshot.connected_ports),
            "devices": len(snapshot.devices),
            "emarked_cables": len(snapshot.emarked_cables),
        },
        "ports": [_port(port) for port in snapshot.ports],
        "buses": [_bus(bus) for bus in snapshot.buses],
        "thunderbolt": [_thunderbolt(port) for port in snapshot.thunderbolt],
        "warnings": list(snapshot.warnings),
    }


def snapshot_to_json(snapshot: Snapshot, *, indent: int | None = 2) -> str:
    """Serialise a snapshot as JSON text."""
    return json.dumps(snapshot_to_dict(snapshot), indent=indent, ensure_ascii=False)
