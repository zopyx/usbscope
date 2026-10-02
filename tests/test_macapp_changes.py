"""Tests for snapshot diffing (plug/unplug detection)."""

from __future__ import annotations

from dataclasses import replace

from usbscope.macapp.changes import (
    ADDED,
    CHANGED,
    REMOVED,
    ChangeSet,
    device_key,
    diff_snapshots,
    port_key,
)
from usbscope.models import Bus, Snapshot, UsbDevice


def _stick() -> UsbDevice:
    return UsbDevice(name="Portable SSD", vendor="Samsung", vendor_id=0x04E8, product_id=0x61F5)


def _add_device(snapshot: Snapshot, device: UsbDevice) -> Snapshot:
    """A snapshot with one more device, attached to an extra bus."""
    return replace(snapshot, buses=(*snapshot.buses, Bus(name="Extra bus", devices=(device,))))


def _drop_device(snapshot: Snapshot, device: UsbDevice) -> Snapshot:
    """A snapshot without ``device`` (removed from the buses and the ports)."""
    wanted = device_key(device)

    def keep(devices: tuple[UsbDevice, ...]) -> tuple[UsbDevice, ...]:
        return tuple(item for item in devices if device_key(item) != wanted)

    return replace(
        snapshot,
        buses=tuple(replace(bus, devices=keep(bus.devices)) for bus in snapshot.buses),
        ports=tuple(replace(port, devices=keep(port.devices)) for port in snapshot.ports),
    )


def test_device_key_prefers_the_serial() -> None:
    with_serial = UsbDevice(name="Stick", vendor_id=0x1050, product_id=0x0407, serial="ABC123")
    assert device_key(with_serial) == "device:serial:ABC123"

    without = UsbDevice(name="Stick", vendor_id=0x1050, product_id=0x0407, location_id=0x01100000)
    assert device_key(without) == "device:1050:0407:01100000:stick"


def test_device_key_separates_identical_models(snapshot: Snapshot) -> None:
    def at(location: int) -> UsbDevice:
        return UsbDevice(name="Webcam", vendor_id=0x046D, product_id=0x0825, location_id=location)

    assert device_key(at(0x01100000)) != device_key(at(0x01200000))


def test_the_first_read_reports_nothing(snapshot: Snapshot) -> None:
    changes = diff_snapshots(None, snapshot)
    assert changes.is_empty
    assert changes.count == 0
    assert changes.summary() == "no changes"


def test_unchanged_snapshot_is_quiet(snapshot: Snapshot) -> None:
    assert diff_snapshots(snapshot, snapshot).is_empty


def test_plugging_a_device_is_reported(snapshot: Snapshot) -> None:
    stick = _stick()
    changes = diff_snapshots(snapshot, _add_device(snapshot, stick))

    assert [device.name for device in changes.added] == ["Portable SSD"]
    assert changes.removed == ()
    assert changes.changed_ports == ()
    assert changes.count == 1
    assert changes.device_count == 1
    assert changes.summary() == "1 added"
    assert changes.tag(device_key(stick)) == ADDED
    assert changes.tag(device_key(snapshot.devices[0])) is None


def test_unplugging_a_device_is_reported(snapshot: Snapshot) -> None:
    changes = diff_snapshots(snapshot, _drop_device(snapshot, snapshot.devices[0]))

    assert [device.name for device in changes.removed] == ["YubiKey OTP+FIDO+CCID"]
    assert "1 removed" in changes.summary()
    assert changes.tag(device_key(snapshot.devices[0])) == REMOVED


def test_port_state_change_is_reported(snapshot: Snapshot) -> None:
    ports = list(snapshot.ports)
    index = next(index for index, port in enumerate(ports) if not port.connected)
    ports[index] = replace(ports[index], connected=True)
    changes = diff_snapshots(snapshot, replace(snapshot, ports=tuple(ports)))

    assert changes.changed_ports == (port_key(ports[index]),)
    assert changes.tag(port_key(ports[index])) == CHANGED
    assert changes.summary() == "1 port state changed"
    assert changes.device_count == 0


def test_summary_counts_every_kind(snapshot: Snapshot) -> None:
    stick = _stick()
    plugged = _add_device(snapshot, stick)
    assert diff_snapshots(plugged, _drop_device(plugged, stick)).summary() == "1 removed"

    # a port whose state changed next to a freshly plugged device
    ports = list(snapshot.ports)
    ports[0] = replace(ports[0], connected=not ports[0].connected)
    both = diff_snapshots(snapshot, replace(plugged, ports=tuple(ports)))
    assert both.summary() == "1 added · 1 port state changed"
    assert both.count == 2


def test_changeset_can_be_built_by_hand(snapshot: Snapshot) -> None:
    changes = ChangeSet(added=(_stick(),), changed_ports=("port:USB-C@1",))
    assert changes.count == 2
    assert not changes.is_empty
    assert changes.tag("port:USB-C@1") == CHANGED
