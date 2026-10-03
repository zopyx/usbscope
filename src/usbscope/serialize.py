"""Machine readable representation of a snapshot (``usbscope --json``)."""

from __future__ import annotations

import json
from dataclasses import asdict
from typing import Any

from .models import (
    Bus,
    Cable,
    Charging,
    Port,
    PowerOption,
    PowerSource,
    Snapshot,
    ThunderboltPort,
    Transport,
    UsbDevice,
)
from .models_thunderbolt import (
    ThunderboltFabric,
    ThunderboltFabricPort,
    ThunderboltRouter,
    ThunderboltTunnel,
)

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
        "device_class": device.device_class,
        "device_subclass": device.device_subclass,
        "device_protocol": device.device_protocol,
        "class_name": device.class_name,
        "class_text": device.class_text,
        "bcd_usb": device.bcd_usb,
        "max_packet_size0": device.max_packet_size0,
        "num_configurations": device.num_configurations,
        "speed_code": device.speed_code,
        "tier": device.tier,
        "parent": device.parent,
        "address": device.address,
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


def _power_option(option: PowerOption | None) -> dict[str, Any] | None:
    if option is None:
        return None
    return {
        "voltage_mv": option.voltage_mv,
        "max_current_ma": option.max_current_ma,
        "max_power_mw": option.max_power_mw,
        "watts": option.watts,
        "kind": option.kind,
        "kind_label": option.kind_label,
        "uuid": option.uuid,
    }


def _power_source(source: PowerSource) -> dict[str, Any]:
    return {
        "name": source.name,
        "type": source.source_type,
        "priority": source.priority,
        "selected": source.selected,
        "winning": _power_option(source.winning),
        "options": [_power_option(option) for option in source.options],
    }


def _charging(charging: Charging | None) -> dict[str, Any] | None:
    """The live charging telemetry (all values in mV/mA/mW)."""
    return None if charging is None else asdict(charging)


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
        "pin_configuration": {name: value for name, value in port.pin_configuration},
        "usb_mode_type": port.usb_mode_type,
        "accessory_mode": port.accessory_mode,
        "power_mode": port.power_mode,
        "active_power_mode": port.active_power_mode,
        "supported_power_modes": list(port.supported_power_modes),
        "power_current_limits": list(port.power_current_limits),
        "liquid_state": port.liquid_state,
        "liquid_measurement": port.liquid_measurement,
        "liquid_pin": port.liquid_pin,
        "liquid_mitigations": port.liquid_mitigations,
        "liquid_override": port.liquid_override,
        "power_sources": [_power_source(source) for source in port.power_sources],
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


def _tunnel(tunnel: ThunderboltTunnel) -> dict[str, Any]:
    return {
        "protocol": tunnel.protocol,
        "label": tunnel.label,
        "port_number": tunnel.port_number,
        "adapter_type": tunnel.adapter_type,
        "driver": tunnel.driver,
        "driver_class": tunnel.driver_class,
        "device_id": tunnel.device_id,
    }


def _fabric_port(port: ThunderboltFabricPort) -> dict[str, Any]:
    return {
        "number": port.number,
        "label": port.label,
        "protocol": port.protocol,
        "socket_id": port.socket_id,
        "adapter_type": port.adapter_type,
        "current_link_speed": port.current_link_speed,
        "target_link_speed": port.target_link_speed,
        "supported_link_speed": port.supported_link_speed,
        "current_link_width": port.current_link_width,
        "target_link_width": port.target_link_width,
        "supported_link_width": port.supported_link_width,
        "lane": port.lane,
        "dual_link_port": port.dual_link_port,
        "link_bandwidth": port.link_bandwidth,
        "max_credits": port.max_credits,
        "max_in_hop_id": port.max_in_hop_id,
        "max_out_hop_id": port.max_out_hop_id,
        "upstream_port_number": port.upstream_port_number,
        "restricted": port.restricted,
    }


def _router(router: ThunderboltRouter) -> dict[str, Any]:
    return {
        "router_id": router.router_id,
        "uid": router.uid,
        "vendor_id": router.vendor_id,
        "vendor_name": router.vendor_name,
        "device_model_name": router.device_model_name,
        "device_model_id": router.device_model_id,
        "device_model_revision": router.device_model_revision,
        "thunderbolt_version": router.thunderbolt_version,
        "depth": router.depth,
        "route_string": router.route_string,
        "max_port_number": router.max_port_number,
        "ports": [_fabric_port(port) for port in router.ports],
        "tunnels": [_tunnel(tunnel) for tunnel in router.tunnels],
    }


def _fabric(fabric: ThunderboltFabric) -> dict[str, Any]:
    return {"routers": [_router(router) for router in fabric.routers]}


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
        "thunderbolt_fabric": _fabric(snapshot.thunderbolt_fabric),
        "charging": _charging(snapshot.charging),
        "warnings": list(snapshot.warnings),
    }


def snapshot_to_json(snapshot: Snapshot, *, indent: int | None = 2) -> str:
    """Serialise a snapshot as JSON text."""
    return json.dumps(snapshot_to_dict(snapshot), indent=indent, ensure_ascii=False)
