"""Tests for the ioreg port-controller adapter against a real captured plist."""

from __future__ import annotations

from tests.conftest import fixture_plist
from usbscope.models import UsbMode
from usbscope.sources import IoregSource


def test_ports_from_real_capture(ioreg: IoregSource) -> None:
    ports, warnings = ioreg.ports()
    assert warnings == ()
    assert [port.description for port in ports] == [
        "Port-HDMI@1",
        "Port-MagSafe 3@1",
        "Port-SD Card@1",
        "Port-USB-C@1",
        "Port-USB-C@2",
        "Port-USB-C@3",
    ]
    names = {port.description: port for port in ports}
    assert names["Port-USB-C@3"].name == "USB-C@3"
    assert names["Port-MagSafe 3@1"].kind == "MagSafe 3"
    assert [port.name for port in ports if port.kind == "USB-C"] == [
        "USB-C@1",
        "USB-C@2",
        "USB-C@3",
    ]


def test_device_and_transport_of_connected_port(ioreg: IoregSource) -> None:
    ports, _warnings = ioreg.ports()
    port = next(item for item in ports if item.description == "Port-USB-C@3")
    assert port.connected is True
    assert port.number == 3

    # the YubiKey hangs off the USB2 transport of that port
    assert [device.name for device in port.devices] == ["YubiKey OTP+FIDO+CCID"]
    device = port.devices[0]
    assert (device.vendor_id, device.product_id) == (0x1050, 0x0407)
    assert device.location_id == 0x01100000
    assert device.version == "0x0543"
    assert device.port == "USB-C@3"
    assert device.transport == "USB2"
    assert device.restricted is False

    usb2 = port.transport("USB2")
    assert usb2 is not None
    assert usb2.active is True
    assert usb2.mode is UsbMode.FULL_SPEED
    assert usb2.rate_text == "12 Mbps (Full Speed)"
    assert usb2.data_role == "Host"
    assert usb2.hash_status == "Cached"
    assert usb2.trm_state == "Limited"
    assert usb2.trm_profile == "Ask for New Accessories"

    # the idle USB3 transport is restricted by macOS in this capture
    usb3 = port.transport("USB3")
    assert usb3 is not None
    assert usb3.active is False
    assert usb3.restricted is True
    assert port.mode is UsbMode.FULL_SPEED  # the active transport wins


def test_cable_reports_partner_not_emarker(ioreg: IoregSource) -> None:
    """The SOP node is the PD partner; without SOP'/SOP'' no e-marker may be claimed."""
    ports, _warnings = ioreg.ports()
    charger = next(item for item in ports if item.description == "Port-USB-C@1")
    assert charger.connected is True
    assert charger.cable.attached is True
    assert charger.cable.emarker is False
    assert charger.cable.kind == "unknown"
    assert charger.cable.pd_spec_revision == 3  # SOP specification revision
    assert charger.power_in == ("USB-PD", "Brick ID", "TypeC")
    assert charger.usb_transport is None  # nothing negotiated a USB data link
    assert charger.mode is UsbMode.UNKNOWN

    free_port = next(item for item in ports if item.description == "Port-USB-C@2")
    assert free_port.connected is False
    assert free_port.cable.attached is False
    assert free_port.cable.kind == "–"


def test_liquid_detection_and_firmware(ioreg: IoregSource) -> None:
    ports, _warnings = ioreg.ports()
    for port in ports:
        if port.kind != "USB-C":
            continue
        assert port.liquid_detected is False
        assert port.firmware == "0x00872000"  # raw port controller firmware blob


def test_hdmi_port_has_displayport_transport(ioreg: IoregSource) -> None:
    ports, _warnings = ioreg.ports()
    hdmi = next(item for item in ports if item.description == "Port-HDMI@1")
    assert hdmi.kind == "HDMI"
    transport = hdmi.transport("DisplayPort")
    assert transport is not None
    assert transport.active is False
    assert transport.data_role == "Source"
    assert transport.lanes == 0


def test_parsing_is_pure_and_does_not_mutate_the_plist() -> None:
    from usbscope.sources.ioreg import parse_ports

    tree = fixture_plist("ioport.plist")
    first = parse_ports(tree)
    second = parse_ports(tree)
    assert first == second
    assert first  # the fixture really contains ports


def test_ioreg_failure_is_reported() -> None:
    from usbscope.sources.shell import CommandResult

    def failing(argv: list[str]) -> CommandResult:
        return CommandResult(tuple(argv), 1, error="ioreg not found")

    ports, warnings = IoregSource(runner=failing).ports()
    assert ports == ()
    assert warnings == ("ioreg not found",)
