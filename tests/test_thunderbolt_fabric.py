"""Tests for the USB4/Thunderbolt fabric adapter (routers, ports, tunnels).

The parser is pinned against a real ``ioreg -r -c IOThunderboltSwitch`` capture
(three host routers, 6 ports each) and against a synthetic daisy chain, because
this machine has no downstream router to capture.
"""

from __future__ import annotations

import plistlib
from typing import cast

import pytest

from usbscope.models import Snapshot
from usbscope.models_thunderbolt import ThunderboltFabric, protocol_kind
from usbscope.serialize import snapshot_to_dict
from usbscope.sources.shell import CommandResult
from usbscope.sources.thunderbolt import Runner, ThunderboltFabricSource, parse_fabric

from .conftest import fixture_bytes, fixture_plist, make_runner


def _fabric(name: str = "tb_switch.plist") -> ThunderboltFabric:
    return parse_fabric(fixture_plist(name))


# --------------------------------------------------------------------------- real capture


def test_real_capture_has_three_host_routers() -> None:
    fabric = _fabric()
    assert len(fabric.routers) == 3
    assert [router.router_id for router in fabric.routers] == [0, 1, 2]
    assert len({router.uid for router in fabric.routers}) == 3
    assert {router.depth for router in fabric.routers} == {0}
    assert {router.vendor_name for router in fabric.routers} == {"Apple Inc."}
    assert {router.vendor_id for router in fabric.routers} == {0x5AC}
    assert {router.thunderbolt_version for router in fabric.routers} == {32}
    assert {router.max_port_number for router in fabric.routers} == {7}


def test_real_capture_ports_and_tunnels() -> None:
    fabric = _fabric()
    assert [len(router.ports) for router in fabric.routers] == [6, 6, 6]
    assert [len(router.tunnels) for router in fabric.routers] == [4, 4, 4]
    assert len(fabric.ports) == 18
    assert len(fabric.tunnels) == 12


def test_real_capture_protocol_tokens() -> None:
    """The port label decides the protocol; the raw Adapter Type is kept verbatim."""
    router = _fabric().routers[0]
    assert [(port.number, port.protocol) for port in router.ports] == [
        (1, "thunderbolt"),
        (2, "thunderbolt"),
        (3, "pcie"),
        (4, "usb"),
        (5, "displayport"),
        (6, "displayport"),
    ]
    assert [tunnel.protocol for tunnel in router.tunnels] == [
        "pcie",
        "usb",
        "displayport",
        "displayport",
    ]


def test_real_capture_link_facts_are_verbatim() -> None:
    """Current/target/supported speed and width are raw switch enumerations."""
    port = _fabric().routers[0].ports[0]
    assert port.label == "Thunderbolt Port"
    assert port.socket_id == "1"
    assert port.adapter_type == 1
    assert port.current_link_speed == 8
    assert port.target_link_speed == 12
    assert port.supported_link_speed == 12
    assert port.current_link_width == 1
    assert port.target_link_width == 1
    assert port.supported_link_width == 2
    assert port.lane == 1
    assert port.dual_link_port == 2
    assert port.link_bandwidth == 100
    assert port.max_credits == 174
    assert port.max_in_hop_id == 22
    assert port.max_out_hop_id == 22
    assert port.restricted is False
    # macOS publishes the TRM restriction only on the dual-link port 1
    assert _fabric().routers[0].ports[1].restricted is None


def test_real_capture_tunnel_drivers() -> None:
    tunnels = {tunnel.port_number: tunnel for tunnel in _fabric().routers[0].tunnels}
    pcie = tunnels[3]
    assert pcie.protocol == "pcie"
    assert pcie.label == "PCIe Adapter"
    assert pcie.adapter_type == 1048833
    assert pcie.driver == "com.apple.driver.AppleThunderboltPCIDownAdapter"
    assert pcie.driver_class == "AppleThunderboltPCIDownAdapterType5"
    assert pcie.device_id == "0x00002000&0x0000ff00"
    # the USB/DP adapters publish no Device ID
    assert tunnels[4].driver == "com.apple.driver.AppleThunderboltUSBDownAdapter"
    assert tunnels[4].device_id is None


# --------------------------------------------------------------------------- synthetic


def test_synthetic_daisy_chain() -> None:
    """A downstream router below a port: depth 1, its own ports and tunnels."""
    fabric = _fabric("tb_switch_synthetic.plist")
    assert [router.depth for router in fabric.routers] == [0, 1]
    assert [router.router_id for router in fabric.routers] == [0, 1]
    downstream = fabric.routers[1]
    assert downstream.route_string == 256
    assert downstream.max_port_number == 5
    assert len(downstream.ports) == 2
    assert [tunnel.protocol for tunnel in downstream.tunnels] == ["usb"]


def test_synthetic_covers_restriction_unknown_and_missing_facts() -> None:
    router = _fabric("tb_switch_synthetic.plist").routers[0]
    assert router.ports[0].restricted is True
    vendor = router.ports[3]
    assert vendor.label == "Vendor Link Adapter"
    assert vendor.protocol == "unknown"
    assert router.tunnels[1].protocol == "unknown"
    # a port whose link facts the OS did not publish stays null, never 0
    assert vendor.current_link_speed is None
    assert vendor.max_credits is None
    assert vendor.lane is None


@pytest.mark.parametrize(
    ("label", "expected"),
    [
        ("Thunderbolt Port", "thunderbolt"),
        ("PCIe Adapter", "pcie"),
        ("USB Adapter", "usb"),
        ("DP or HDMI Adapter", "displayport"),
        ("  usb adapter  ", "usb"),
        ("Vendor Link Adapter", "unknown"),
        (None, "unknown"),
        ("", "unknown"),
    ],
)
def test_protocol_kind_mapping(label: str | None, expected: str) -> None:
    assert protocol_kind(label) == expected


# --------------------------------------------------------------------------- source


def test_source_serves_the_capture() -> None:
    runner = cast(Runner, make_runner({"IOThunderboltSwitch": "tb_switch.plist"}))
    fabric, warnings = ThunderboltFabricSource(runner=runner).fabric()
    assert warnings == ()
    assert len(fabric.routers) == 3


def test_empty_payload_is_not_a_warning() -> None:
    """A Mac without Thunderbolt reports no switch — that is not a failure."""
    empty = plistlib.dumps([])
    source = ThunderboltFabricSource(runner=lambda argv: CommandResult(tuple(argv), 0, empty))
    fabric, warnings = source.fabric()
    assert fabric.routers == ()
    assert warnings == ()


def test_failing_command_is_reported_not_raised() -> None:
    source = ThunderboltFabricSource(
        runner=lambda argv: CommandResult(tuple(argv), 127, error="ioreg not found")
    )
    fabric, warnings = source.fabric()
    assert fabric.routers == ()
    assert warnings == ("ioreg not found",)


def test_unparsable_output_is_reported() -> None:
    source = ThunderboltFabricSource(
        runner=lambda argv: CommandResult(tuple(argv), 0, b"not a plist at all")
    )
    _fabric, warnings = source.fabric()
    assert warnings and "unparsable" in warnings[0]


def test_unexpected_structure_is_reported() -> None:
    scalar = plistlib.dumps("just a string")
    source = ThunderboltFabricSource(runner=lambda argv: CommandResult(tuple(argv), 0, scalar))
    _fabric, warnings = source.fabric()
    assert warnings == ("ioreg returned an unexpected structure",)


def test_parse_accepts_a_single_router_dict() -> None:
    """`ioreg` returns an array, but a lone switch must not be dropped."""
    payload = plistlib.loads(fixture_bytes("tb_switch.plist"))
    assert isinstance(payload, list)
    assert len(parse_fabric(payload[0]).routers) == 1


# --------------------------------------------------------------------------- snapshot wiring


def test_fabric_is_part_of_the_snapshot(snapshot: Snapshot) -> None:
    assert len(snapshot.thunderbolt_fabric.routers) == 3
    assert len(snapshot.thunderbolt_fabric.ports) == 18
    assert len(snapshot.thunderbolt_fabric.tunnels) == 12
    assert snapshot.warnings == ()


def test_fabric_json_block(snapshot: Snapshot) -> None:
    """The snapshot carries the fabric under its own key without a schema bump."""
    data = snapshot_to_dict(snapshot)
    assert data["schema_version"] == 1
    block = data["thunderbolt_fabric"]
    assert len(block["routers"]) == 3
    router = block["routers"][0]
    assert router["router_id"] == 0
    assert router["uid"] == 408840496304102592
    assert router["thunderbolt_version"] == 32
    assert [port["protocol"] for port in router["ports"]] == [
        "thunderbolt",
        "thunderbolt",
        "pcie",
        "usb",
        "displayport",
        "displayport",
    ]
    assert router["ports"][0]["current_link_speed"] == 8
    assert router["ports"][0]["restricted"] is False
    assert [tunnel["protocol"] for tunnel in router["tunnels"]] == [
        "pcie",
        "usb",
        "displayport",
        "displayport",
    ]
    assert router["tunnels"][0]["driver"] == "com.apple.driver.AppleThunderboltPCIDownAdapter"
