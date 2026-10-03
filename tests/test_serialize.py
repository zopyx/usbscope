"""Tests for the JSON serialisation."""

from __future__ import annotations

import json

from usbscope.models import Snapshot
from usbscope.serialize import SCHEMA_VERSION, snapshot_to_dict, snapshot_to_json


def test_dict_shape(snapshot: Snapshot) -> None:
    data = snapshot_to_dict(snapshot)
    assert data["schema_version"] == SCHEMA_VERSION
    assert data["model"] == "MacBook Pro"
    assert data["summary"] == {
        "ports": 6,
        "connected_ports": 2,
        "devices": 1,
        "emarked_cables": 0,
    }
    assert len(data["ports"]) == 6
    assert len(data["buses"]) == 3
    assert len(data["thunderbolt"]) == 3
    assert data["warnings"] == []


def test_port_payload(snapshot: Snapshot) -> None:
    port = next(item for item in snapshot_to_dict(snapshot)["ports"] if item["name"] == "USB-C@3")
    assert port["connected"] is True
    assert port["mode"] == "full_speed"
    assert port["mode_label"] == "USB 1.1 Full-Speed · 12 Mbit/s"
    assert port["cable"]["emarker"] is False
    assert port["cable"]["hash_status"] == "Not Set"
    assert port["power_in"] == []
    usb2 = next(item for item in port["transports"] if item["kind"] == "USB2")
    assert usb2["active"] is True
    assert usb2["mode"] == "full_speed"
    assert usb2["rate"] == "12 Mbps (Full Speed)"
    assert usb2["trm_state"] == "Limited"
    assert port["devices"][0]["id"] == "0x1050:0x0407"


def test_port_payload_carries_the_optional_controller_details(snapshot: Snapshot) -> None:
    port = next(item for item in snapshot_to_dict(snapshot)["ports"] if item["name"] == "USB-C@3")
    assert port["pin_configuration"] == {
        "rx1": 0,
        "rx2": 4,
        "tx1": 0,
        "tx2": 3,
        "sbu1": 0,
        "sbu2": 0,
    }
    assert port["usb_mode_type"] == 2
    assert port["accessory_mode"] == 0
    assert port["power_mode"] == 1
    assert port["active_power_mode"] == 1
    assert port["supported_power_modes"] == [1, 3]
    assert port["power_current_limits"] == [0, 0, 0, 0, 0]
    assert port["liquid_state"] == "Idle"
    assert port["liquid_measurement"] == "No Error"
    assert port["liquid_pin"] == "Reference"
    assert port["liquid_mitigations"] is False
    assert port["liquid_override"] is False

    # a receptacle without the optional data reports empty/None instead of a guess
    hdmi = next(item for item in snapshot_to_dict(snapshot)["ports"] if item["name"] == "HDMI@1")
    assert hdmi["pin_configuration"] == {}
    assert hdmi["usb_mode_type"] is None
    assert hdmi["supported_power_modes"] == []
    assert hdmi["liquid_state"] is None


def test_port_payload_carries_the_power_contract(snapshot: Snapshot) -> None:
    ports = {port["name"]: port for port in snapshot_to_dict(snapshot)["ports"]}
    sources = ports["USB-C@1"]["power_sources"]
    assert [source["name"] for source in sources] == ["USB-PD", "Brick ID", "TypeC"]
    usb_pd = sources[0]
    assert usb_pd["selected"] is True
    assert usb_pd["type"] == 2
    assert usb_pd["priority"] == 1000
    winning = usb_pd["winning"]
    assert winning["voltage_mv"] == 20000
    assert winning["max_current_ma"] == 5000
    assert winning["max_power_mw"] == 100000
    assert winning["watts"] == 100.0
    # the PDO type and the controller's option identity
    assert winning["kind"] == "fixed"
    assert winning["kind_label"] == "fixed"
    assert winning["uuid"] == "BAC8D9DA-DC62-4A85-8590-D9037ACB133B"
    assert sorted(option["max_power_mw"] for option in usb_pd["options"]) == [
        15000,
        27000,
        45000,
        100000,
    ]
    assert ports["USB-C@1"]["power_sources"][2]["options"][0]["watts"] == 15.0
    assert ports["USB-C@2"]["power_sources"] == []  # nothing attached


def test_charging_payload(snapshot: Snapshot) -> None:
    charging = snapshot_to_dict(snapshot)["charging"]
    assert charging is not None
    assert charging["connected"] is True
    assert charging["charging"] is True
    assert charging["state_of_charge"] == 100
    assert charging["system_power_in_mw"] == 27575
    assert charging["adapter_power_mw"] == 70000
    assert charging["battery_current_ma"] == 887


def test_a_desktop_serialises_no_charging_block() -> None:
    from datetime import datetime

    without = Snapshot(host="mac", os_version="27.0.1", seen_at=datetime(2026, 10, 2))
    assert snapshot_to_dict(without)["charging"] is None


def test_lossless_json_round_trip(snapshot: Snapshot) -> None:
    text = snapshot_to_json(snapshot)
    assert json.loads(text) == snapshot_to_dict(snapshot)
    assert "\n" in text  # pretty printed by default
    assert snapshot_to_json(snapshot, indent=None).startswith('{"schema_version"')
