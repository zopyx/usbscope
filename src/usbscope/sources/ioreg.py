"""Adapter for the IORegistry: USB-C ports, cables and per-port transports.

``ioreg -a -l -w0 -p IOPort`` returns the "hardware port manager" view of every
receptacle of the machine: the negotiated transports (CC, USB2, USB3,
DisplayPort, SD), the electronically marked cable data (the SOP node), liquid
detection and the accessory restrictions applied by macOS.  The plist is parsed
straight from stdout - no entitlements, no private framework, no sudo.
"""

from __future__ import annotations

import plistlib
from collections.abc import Callable, Iterator
from dataclasses import replace
from typing import Any

from ..models import Cable, Port, PowerOption, PowerSource, Transport, UsbDevice
from .shell import CommandResult, run_command, system_binary

__all__ = ["IoregSource", "parse_ports"]

Runner = Callable[[list[str]], CommandResult]

IOREG = system_binary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")

_DEVICE_MARKERS = ("UsbLinkSpeed", "idVendor", "USB Product Name", "UsbDeviceSignature")
_TRANSPORT_KINDS = ("CC", "USB2", "USB3", "USB4", "DisplayPort", "SD")
# canonical order of the ``Pin Configuration`` dict of a receptacle
_PIN_ORDER = ("rx1", "rx2", "tx1", "tx2", "sbu1", "sbu2")


def _iter_tree(node: Any, depth: int = 0) -> Iterator[tuple[dict[str, Any], int]]:
    """Yield every node of a parsed IORegistry plist together with its depth."""
    if not isinstance(node, dict):
        return
    yield node, depth
    for child in node.get("IORegistryEntryChildren") or []:
        yield from _iter_tree(child, depth + 1)


def _children(node: dict[str, Any]) -> list[dict[str, Any]]:
    kids = node.get("IORegistryEntryChildren") or []
    return [child for child in kids if isinstance(child, dict)]


def _text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (bytes, bytearray)):
        return bytes(value).hex()
    text = str(value).strip()
    if not text or text.lower() in {"none", "null", "<null>"}:
        return None
    return text


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
        if lowered in {"yes", "true"}:
            return True
        if lowered in {"no", "false"}:
            return False
    return None


def _label(node: dict[str, Any]) -> str:
    return str(node.get("IORegistryEntryName") or node.get("Description") or "?")


def _find(node: dict[str, Any], name: str) -> dict[str, Any] | None:
    """Find a direct child by ``IORegistryEntryName``."""
    for child in _children(node):
        if str(child.get("IORegistryEntryName")) == name:
            return child
    return None


def _format_bcd(value: Any) -> str | None:
    number = _int(value)
    return f"0x{number:04x}" if number is not None else None


def _firmware(raw: Any) -> str | None:
    """Render the raw firmware blob of the port controller as a hex version."""
    if isinstance(raw, (bytes, bytearray)) and raw:
        number = int.from_bytes(bytes(raw).ljust(4, b"\x00")[:4], "big")
        return f"0x{number:08x}"
    return _text(raw)


def _is_device_node(node: dict[str, Any]) -> bool:
    return any(marker in node for marker in _DEVICE_MARKERS)


def _parse_device(node: dict[str, Any], port: Port, transport: Transport) -> UsbDevice:
    speed_bits = _int(node.get("UsbLinkSpeed"))
    speed_mbps = round(speed_bits / 1_000_000) if speed_bits and speed_bits > 100_000 else None
    return UsbDevice(
        name=str(node.get("USB Product Name") or node.get("kUSBProductString") or _label(node)),
        vendor=_text(node.get("USB Vendor Name") or node.get("kUSBVendorString")),
        vendor_id=_int(node.get("idVendor")),
        product_id=_int(node.get("idProduct")),
        location_id=_int(node.get("locationID")),
        speed_mbps=speed_mbps,
        speed_text=f"{speed_mbps} Mbit/s" if speed_mbps else None,
        connection="Removable",
        version=_format_bcd(node.get("bcdDevice")),
        port=port.name,
        port_type=port.kind,
        transport=transport.kind,
        generation=transport.generation,
        restricted=transport.restricted,
        source="ioreg",
    )


def _speed_from_index(index: int | None, kind: str) -> float | None:
    """Map the enumeration values Apple uses on the USB2/USB3 transports."""
    if index is None or index <= 0:
        return None
    if kind.upper().startswith("USB3"):
        return {1: 5000, 2: 10000, 3: 20000}.get(index)
    return {1: 1.5, 2: 12, 3: 480}.get(index)


def _parse_transport(node: dict[str, Any], port: Port) -> tuple[Transport, tuple[UsbDevice, ...]]:
    kind = str(node.get("TransportTypeDescription") or _label(node))
    device_nodes = [
        child for child, _depth in _iter_tree(node) if child is not node and _is_device_node(child)
    ]
    speeds = [
        round(bits / 1_000_000)
        for child in device_nodes
        if (bits := _int(child.get("UsbLinkSpeed"))) and bits > 100_000
    ]
    speed_mbps = max(speeds) if speeds else _speed_from_index(_int(node.get("DataRate")), kind)
    transport = Transport(
        kind=kind,
        active=bool(_bool(node.get("Active"))),
        rate_text=_text(node.get("DataRateDescription") or node.get("LinkRateDescription")),
        speed_mbps=speed_mbps,
        generation=_text(node.get("GenerationDescription")),
        signaling=_text(node.get("SuperSpeedSignalingDescription")),
        data_role=_text(node.get("DataRoleDescription") or node.get("RoleDescription")),
        lanes=_int(node.get("LaneCount")),
        restricted=_bool(node.get("TRM_TransportRestricted")),
        trm_state=_text(node.get("TRM_StateDescription")),
        trm_profile=_text(node.get("TRM_ProfileDescription")),
        hash_status=_text(node.get("HashStatusDescription")),
    )
    return transport, tuple(_parse_device(child, port, transport) for child in device_nodes)


def _parse_cable(port_node: dict[str, Any]) -> Cable:
    cc = _find(port_node, "CC")
    children = _children(cc) if cc is not None else []
    # SOP = the PD port partner (device/charger), SOP'/SOP'' = cable plugs (e-marker).
    partner = next((k for k in children if _is_partner(k)), None)
    plugs = [k for k in children if _is_cable_plug(k)]
    connected = bool(
        _bool(port_node.get("ConnectionActive")) or _bool(port_node.get("IOAccessoryDetect"))
    )
    return Cable(
        attached=connected,
        emarker=bool(plugs),
        active=bool(_bool(port_node.get("ActiveCable"))),
        optical=bool(_bool(port_node.get("OpticalCable"))),
        authentication=_text(cc.get("AuthenticationStatusDescription")) if cc is not None else None,
        hash_status=_text(cc.get("HashStatusDescription")) if cc is not None else None,
        pd_spec_revision=_int(partner.get("Specification Revision")) if partner else None,
    )


def _is_partner(node: dict[str, Any]) -> bool:
    """True for the SOP node (the port partner responding to power delivery)."""
    name = str(node.get("IORegistryEntryName") or node.get("AddressDescription") or "")
    return name.strip().upper() == "SOP"


def _is_cable_plug(node: dict[str, Any]) -> bool:
    """True for SOP'/SOP'' nodes, which only e-marked cables answer."""
    name = str(node.get("IORegistryEntryName") or node.get("AddressDescription") or "")
    return name.strip().upper() in {"SOP'", "SOP''", "SOPP", "SOPPP", "SOP'S", "SOP''S"}


def _power_source_names(node: dict[str, Any]) -> tuple[str, ...]:
    """Names of the power providers a port reports (the Power In feature)."""
    power = _find(node, "Power In")
    if power is None:
        return ()
    return tuple(
        name for child in _children(power) if (name := _text(child.get("PowerSourceName")))
    )


def _power_option_kind(raw: Any) -> str | None:
    """Decode the controller's PDO class (``IOPortFeaturePowerSourceOptionFixed``).

    ``Fixed`` is a normal PDO, ``Adjustable`` is a PPS/APDO, ``Variable`` and
    ``Battery`` are the rarer PDO types. The controller names the class in the
    option's ``Class`` key; unknown classes are lower-cased verbatim.
    """
    if not isinstance(raw, str) or not raw:
        return None
    prefix = "IOPortFeaturePowerSourceOption"
    name = raw[len(prefix) :] if raw.startswith(prefix) else raw
    if not name:
        return None
    return name[0].lower() + name[1:]


def _power_option(raw: Any) -> PowerOption | None:
    """Translate one ``PowerSourceOption`` dict (voltage/current/power capability)."""
    if not isinstance(raw, dict):
        return None
    option = PowerOption(
        max_power_mw=_int(raw.get("Max Power (mW)")),
        max_current_ma=_int(raw.get("Max Current (mA)")),
        voltage_mv=_int(raw.get("Voltage (mV)")),
        kind=_power_option_kind(raw.get("Class")),
        uuid=str(raw["UUID"]) if raw.get("UUID") else None,
    )
    known = option.max_power_mw is not None or option.max_current_ma is not None
    return option if known or option.voltage_mv is not None else None


def _power_sources(node: dict[str, Any]) -> tuple[PowerSource, ...]:
    """Power providers of a port, including the option they negotiated.

    macOS marks the winning provider with ``[*]`` in the registry name and stores
    the agreed option only on that node.
    """
    feature = _find(node, "Power In")
    if feature is None:
        return ()
    sources: list[PowerSource] = []
    for child in _children(feature):
        raw_name = _label(child)
        winner = _power_option(child.get("WinningPowerSourceOption"))
        name = raw_name.replace("[*]", "").strip()
        if not name:
            continue
        sources.append(
            PowerSource(
                name=name,
                source_type=_int(child.get("PowerSourceType")),
                priority=_int(child.get("Priority")),
                selected="[*]" in raw_name or winner is not None,
                winning=winner,
                options=tuple(
                    option
                    for option in (
                        _power_option(entry) for entry in child.get("PowerSourceOptions") or []
                    )
                    if option is not None
                ),
            )
        )
    return tuple(sources)


def _int_tuple(value: Any) -> tuple[int, ...]:
    """Coerce a plist list of numbers into a tuple, dropping unparsable entries."""
    if not isinstance(value, (list, tuple)):
        return ()
    numbers = (_int(item) for item in value)
    return tuple(number for number in numbers if number is not None)


def _pins(node: dict[str, Any]) -> tuple[tuple[str, int], ...]:
    """USB-C pin assignment of the receptacle (``Pin Configuration``)."""
    raw = node.get("Pin Configuration")
    if not isinstance(raw, dict):
        return ()
    pairs = ((name, _int(raw.get(name))) for name in _PIN_ORDER)
    return tuple((name, value) for name, value in pairs if value is not None)


def _is_port_node(node: dict[str, Any]) -> bool:
    return bool(node.get("PortDescription") and node.get("PortTypeDescription"))


def _parse_port(node: dict[str, Any]) -> Port:
    liquid = _find(node, "LDCM")
    liquid_detected = _bool(node.get("LDCM_LiquidDetected"))
    if liquid_detected is None and liquid is not None:
        liquid_detected = _bool(liquid.get("LiquidDetected"))
    port = Port(
        description=str(node.get("PortDescription") or node.get("Description") or "port"),
        kind=str(node.get("PortTypeDescription") or "unknown"),
        connected=bool(_bool(node.get("ConnectionActive"))),
        number=_int(node.get("PortNumber")),
        connect_type=_text(node.get("IOAccessoryUSBConnectString"))
        or _text(node.get("IOAccessoryUSBConnectType")),
        super_speed_active=_bool(node.get("IOAccessoryUSBSuperSpeedActive")),
        plug_orientation=_int(node.get("PlugOrientation")),
        displayport_pin_assignment=_int(node.get("DisplayPortPinAssignment")),
        liquid_detected=liquid_detected,
        authorization=_text(node.get("UserAuthorizationStatusDescription")),
        firmware=_firmware(node.get("FW Version")),
        power_in=_power_source_names(node),
        pin_configuration=_pins(node),
        usb_mode_type=_int(node.get("IOAccessoryUSBModeType")),
        accessory_mode=_int(node.get("AccessoryMode")),
        power_mode=_int(node.get("IOAccessoryPowerMode")),
        active_power_mode=_int(node.get("IOAccessoryActivePowerMode")),
        supported_power_modes=_int_tuple(node.get("IOAccessorySupportedPowerModes")),
        power_current_limits=_int_tuple(node.get("IOAccessoryPowerCurrentLimits")),
        liquid_state=_text(node.get("LDCM_StateDescription")),
        liquid_measurement=_text(node.get("LDCM_MeasurementStatusDescription")),
        liquid_pin=_text(node.get("LDCMPinDescription")),
        liquid_mitigations=_bool(node.get("LDCM_MitigationsEnabled")),
        liquid_override=_bool(node.get("LDCM_UserOverrideActive")),
        power_sources=_power_sources(node),
        cable=_parse_cable(node),
    )
    transports: list[Transport] = []
    devices: list[UsbDevice] = []
    for child in _children(node):
        kind = str(child.get("TransportTypeDescription") or "")
        if kind not in _TRANSPORT_KINDS:
            continue
        transport, found = _parse_transport(child, port)
        transports.append(transport)
        devices.extend(found)
    return replace(port, transports=tuple(transports), devices=tuple(devices))


def parse_ports(root: dict[str, Any]) -> tuple[Port, ...]:
    """Translate a parsed ``-p IOPort`` plist into domain ports, without duplicates."""
    ports: dict[str, Port] = {}
    for node, _depth in _iter_tree(root):
        if not _is_port_node(node):
            continue
        port = _parse_port(node)
        existing = ports.get(port.description)
        if existing is None or (port.connected and not existing.connected):
            ports[port.description] = port
    return tuple(sorted(ports.values(), key=lambda item: (item.kind, item.number or 0)))


class IoregSource:
    """Reads the IORegistry port tree."""

    def __init__(self, runner: Runner | None = None) -> None:
        self._run = runner or run_command

    def ioport_tree(self) -> tuple[dict[str, Any] | None, str | None]:
        """Return the parsed ``IOPort`` plane and an optional warning."""
        result = self._run([IOREG, "-a", "-l", "-w0", "-p", "IOPort"])
        if not result.ok:
            return None, result.error or "ioreg failed"
        try:
            tree = plistlib.loads(result.stdout)
        except Exception:
            return None, "ioreg returned unparsable output"
        if not isinstance(tree, dict):
            return None, "ioreg returned an unexpected structure"
        return tree, None

    def ports(self) -> tuple[tuple[Port, ...], tuple[str, ...]]:
        """Return the ports of the machine plus any non-fatal warnings."""
        tree, warning = self.ioport_tree()
        if tree is None:
            return (), (warning,) if warning else ()
        ports = parse_ports(tree)
        if not ports:
            return (), ("no port data reported by the hardware port manager",)
        return ports, ()
