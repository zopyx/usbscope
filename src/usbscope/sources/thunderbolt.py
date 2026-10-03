"""Adapter for the USB4/Thunderbolt *fabric* (``ioreg -c IOThunderboltSwitch``).

``ioreg -r -c IOThunderboltSwitch -a -l -w0`` returns every USB4 router the host
publishes: the switches (host routers and, when a device is daisy chained,
downstream routers), their ports with the link facts the switch reports
(current/target/supported link speed and width, lane, dual-link pairing, credits,
hop IDs) and — below the adapter ports — the kernel driver nodes that terminate a
tunneled protocol (PCIe, USB, DisplayPort).

The plist is parsed straight from stdout: no entitlements, no private framework,
no sudo. ``ioreg -p IOThunderbolt`` (the plane root) carries only plane metadata
and no routers, so the class query is what usbscope uses.
"""

from __future__ import annotations

import plistlib
from collections.abc import Callable, Iterator
from typing import Any

from ..models_thunderbolt import (
    ThunderboltFabric,
    ThunderboltFabricPort,
    ThunderboltRouter,
    ThunderboltTunnel,
    protocol_kind,
)
from .shell import CommandResult, run_command, system_binary

__all__ = ["ThunderboltFabricSource", "parse_fabric"]

Runner = Callable[[list[str]], CommandResult]

IOREG = system_binary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")

_SWITCH_CLASS_PREFIX = "IOThunderboltSwitch"
_PORT_CLASS = "IOThunderboltPort"


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


def _io_class(node: dict[str, Any]) -> str:
    return str(node.get("IOObjectClass") or "")


def _is_switch(node: dict[str, Any]) -> bool:
    return _io_class(node).startswith(_SWITCH_CLASS_PREFIX)


def _is_port(node: dict[str, Any]) -> bool:
    return _io_class(node) == _PORT_CLASS


def _port_children(node: dict[str, Any]) -> list[dict[str, Any]]:
    return [child for child in _children(node) if _is_port(child)]


def _adapter_node(port_node: dict[str, Any]) -> dict[str, Any] | None:
    """The driver node macOS publishes below a tunneled port, if any.

    A native Thunderbolt link port has no child; a PCIe/USB/DisplayPort port
    carries exactly one adapter node. A daisy-chained router appears as a switch
    child instead, so switches are never mistaken for an adapter.
    """
    for child in _children(port_node):
        if not _is_port(child) and not _is_switch(child):
            return child
    return None


def _tunnel(port: ThunderboltFabricPort, node: dict[str, Any]) -> ThunderboltTunnel | None:
    """Build the tunnel endpoint of a port, or ``None`` for a native link port.

    A tunnel requires the adapter driver node as evidence; the protocol token is
    the port's own label. A vendor adapter with an unknown label therefore shows
    up as a tunnel of protocol ``unknown`` instead of being dropped.
    """
    adapter = _adapter_node(node)
    if adapter is None:
        return None
    return ThunderboltTunnel(
        protocol=port.protocol,
        label=port.label,
        port_number=port.number,
        adapter_type=port.adapter_type,
        driver=_text(adapter.get("CFBundleIdentifier")),
        driver_class=_text(adapter.get("IOObjectClass")),
        device_id=_text(adapter.get("Device ID")),
    )


def _parse_port(node: dict[str, Any]) -> ThunderboltFabricPort:
    label = _text(node.get("Description")) or "?"
    return ThunderboltFabricPort(
        label=label,
        protocol=protocol_kind(label),
        number=_int(node.get("Port Number")),
        socket_id=_text(node.get("Socket ID")),
        adapter_type=_int(node.get("Adapter Type")),
        current_link_speed=_int(node.get("Current Link Speed")),
        target_link_speed=_int(node.get("Target Link Speed")),
        supported_link_speed=_int(node.get("Supported Link Speed")),
        current_link_width=_int(node.get("Current Link Width")),
        target_link_width=_int(node.get("Target Link Width")),
        supported_link_width=_int(node.get("Supported Link Width")),
        lane=_int(node.get("Lane")),
        dual_link_port=_int(node.get("Dual-Link Port")),
        link_bandwidth=_int(node.get("Link Bandwidth")),
        max_credits=_int(node.get("Max Credits")),
        max_in_hop_id=_int(node.get("Max In Hop ID")),
        max_out_hop_id=_int(node.get("Max Out Hop ID")),
        upstream_port_number=_int(node.get("Upstream Port Number")),
        restricted=_bool(node.get("TRM Transport Restricted")),
    )


def _parse_router(node: dict[str, Any]) -> ThunderboltRouter:
    ports: list[ThunderboltFabricPort] = []
    tunnels: list[ThunderboltTunnel] = []
    for port_node in _port_children(node):
        port = _parse_port(port_node)
        ports.append(port)
        tunnel = _tunnel(port, port_node)
        if tunnel is not None:
            tunnels.append(tunnel)
    return ThunderboltRouter(
        router_id=_int(node.get("Router ID")),
        uid=_int(node.get("UID")),
        vendor_id=_int(node.get("Vendor ID")),
        vendor_name=_text(node.get("Device Vendor Name")),
        device_model_name=_text(node.get("Device Model Name")),
        device_model_id=_int(node.get("Device Model ID")),
        device_model_revision=_int(node.get("Device Model Revision")),
        thunderbolt_version=_int(node.get("Thunderbolt Version")),
        depth=_int(node.get("Depth")),
        route_string=_int(node.get("Route String")),
        max_port_number=_int(node.get("Max Port Number")),
        ports=tuple(ports),
        tunnels=tuple(tunnels),
    )


def _switch_nodes(node: dict[str, Any]) -> Iterator[dict[str, Any]]:
    """Yield every switch node at or below ``node``, host routers first.

    A daisy-chained router hangs below a port of its upstream router, so the
    walk descends through the ports to find it.
    """
    if _is_switch(node):
        yield node
        for port_node in _port_children(node):
            for child in _children(port_node):
                yield from _switch_nodes(child)
        return
    for child in _children(node):
        yield from _switch_nodes(child)


def parse_fabric(root: Any) -> ThunderboltFabric:
    """Translate a parsed ``-c IOThunderboltSwitch`` plist into the fabric."""
    entries = root if isinstance(root, list) else [root]
    routers: list[ThunderboltRouter] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        routers.extend(_parse_router(node) for node in _switch_nodes(entry))
    return ThunderboltFabric(routers=tuple(routers))


class ThunderboltFabricSource:
    """Reads the USB4/Thunderbolt fabric the switches publish."""

    def __init__(self, runner: Runner | None = None) -> None:
        self._run = runner or run_command

    def fabric_tree(self) -> tuple[Any, str | None]:
        """The parsed ``IOThunderboltSwitch`` payload and an optional warning."""
        result = self._run([IOREG, "-r", "-c", "IOThunderboltSwitch", "-a", "-l", "-w0"])
        if not result.ok:
            return None, result.error or "ioreg failed"
        try:
            tree = plistlib.loads(result.stdout)
        except Exception:
            return None, "ioreg returned unparsable output"
        if not isinstance(tree, (dict, list)):
            return None, "ioreg returned an unexpected structure"
        return tree, None

    def fabric(self) -> tuple[ThunderboltFabric, tuple[str, ...]]:
        """The fabric of the machine plus any non-fatal warnings.

        An empty result is not a failure: a Mac without Thunderbolt reports no
        switch at all, so it yields an empty fabric and no warning.
        """
        tree, warning = self.fabric_tree()
        if tree is None:
            return ThunderboltFabric(), (warning,) if warning else ()
        return parse_fabric(tree), ()
