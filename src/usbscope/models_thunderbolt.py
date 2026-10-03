"""Domain model of the Thunderbolt/USB4 *fabric* — routers, ports and tunnels.

Where :class:`usbscope.models.ThunderboltPort` is the ``system_profiler`` view of
a *receptacle* (one physical socket, its status and the cable capability), the
fabric is the ``ioreg -c IOThunderboltSwitch`` view of the USB4 *topology*: the
switches (routers) the host exposes, the ports of each router with the link facts
the switch publishes, and the down-adapter ports that carry a tunneled protocol
(PCIe, USB, DisplayPort).

The two describe the same hardware from two angles and are deliberately kept
apart instead of being averaged; both can be present in one snapshot.
"""

from __future__ import annotations

from dataclasses import dataclass, field

__all__ = [
    "ThunderboltFabric",
    "ThunderboltFabricPort",
    "ThunderboltRouter",
    "ThunderboltTunnel",
    "protocol_kind",
]

# `Description` values macOS uses for a port of a switch, mapped to a stable
# token. Anything else stays `unknown` instead of being guessed from the raw
# `Adapter Type` bitfield, whose encoding is not public.
_PROTOCOL_BY_LABEL: dict[str, str] = {
    "thunderbolt port": "thunderbolt",
    "pcie adapter": "pcie",
    "usb adapter": "usb",
    "dp or hdmi adapter": "displayport",
}


def protocol_kind(label: str | None) -> str:
    """Stable protocol token of a switch port (``thunderbolt``, ``pcie`` …).

    ``DP or HDMI Adapter`` (the label macOS uses for a DisplayPort tunnel) maps
    to ``displayport``; an unrecognised label stays ``unknown``.
    """
    if not label:
        return "unknown"
    return _PROTOCOL_BY_LABEL.get(label.strip().lower(), "unknown")


@dataclass(frozen=True, slots=True)
class ThunderboltTunnel:
    """A down-adapter port of a switch: the endpoint of a tunneled protocol.

    ``driver``/``driver_class``/``device_id`` are taken from the adapter node
    macOS publishes below the port and name the kernel driver that terminates
    the tunnel (PCIe, USB, DisplayPort). Whether a tunnel is *established* is
    not part of this plane — the switch only reports the link facts.
    """

    protocol: str
    label: str
    port_number: int | None = None
    adapter_type: int | None = None
    driver: str | None = None
    driver_class: str | None = None
    device_id: str | None = None


@dataclass(frozen=True, slots=True)
class ThunderboltFabricPort:
    """One ``IOThunderboltPort`` of a router, with the link facts it publishes.

    The link speeds and widths are raw enumeration values of the switch: macOS
    publishes them but not their encoding, so they are reported verbatim instead
    of being turned into a Gbit/s number that would be a guess. The same holds
    for ``adapter_type`` (a bitfield) — the human name is the port ``label``.
    """

    label: str
    protocol: str
    number: int | None = None
    socket_id: str | None = None
    adapter_type: int | None = None
    current_link_speed: int | None = None
    target_link_speed: int | None = None
    supported_link_speed: int | None = None
    current_link_width: int | None = None
    target_link_width: int | None = None
    supported_link_width: int | None = None
    lane: int | None = None
    dual_link_port: int | None = None
    link_bandwidth: int | None = None
    max_credits: int | None = None
    max_in_hop_id: int | None = None
    max_out_hop_id: int | None = None
    upstream_port_number: int | None = None
    restricted: bool | None = None


@dataclass(frozen=True, slots=True)
class ThunderboltRouter:
    """One ``IOThunderboltSwitch``: a USB4 router of the fabric.

    ``router_id``/``route_string``/``depth`` are the addressing facts macOS
    publishes; a host router sits at ``depth`` 0 and a daisy-chained device at a
    higher depth. ``tunnels`` lists the down-adapter ports of this router and is
    stored, not derived, so its order matches the registry.
    """

    router_id: int | None = None
    uid: int | None = None
    vendor_id: int | None = None
    vendor_name: str | None = None
    device_model_name: str | None = None
    device_model_id: int | None = None
    device_model_revision: int | None = None
    thunderbolt_version: int | None = None
    depth: int | None = None
    route_string: int | None = None
    max_port_number: int | None = None
    ports: tuple[ThunderboltFabricPort, ...] = ()
    tunnels: tuple[ThunderboltTunnel, ...] = ()


@dataclass(frozen=True, slots=True)
class ThunderboltFabric:
    """Every router macOS exposes, in registry order (host routers first)."""

    routers: tuple[ThunderboltRouter, ...] = field(default_factory=tuple)

    @property
    def ports(self) -> tuple[ThunderboltFabricPort, ...]:
        """All ports of all routers, in router order."""
        return tuple(port for router in self.routers for port in router.ports)

    @property
    def tunnels(self) -> tuple[ThunderboltTunnel, ...]:
        """All tunnel endpoints of all routers, in router order."""
        return tuple(tunnel for router in self.routers for tunnel in router.tunnels)
