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


def test_lossless_json_round_trip(snapshot: Snapshot) -> None:
    text = snapshot_to_json(snapshot)
    assert json.loads(text) == snapshot_to_dict(snapshot)
    assert "\n" in text  # pretty printed by default
    assert snapshot_to_json(snapshot, indent=None).startswith('{"schema_version"')
