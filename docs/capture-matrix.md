# Hardware capture matrix

The capture suite is fixture-driven. Each capture must record macOS version,
architecture, hardware provenance, source commands, expected normalized values,
and parser tests. Required classes are:

- Apple Silicon and Intel hosts
- direct ports, hubs, docks, USB4 hubs, and Thunderbolt devices
- storage, HID, displays, and charge-only connections

Unknown keys and OS-specific field differences are warnings, not parser-crash
conditions. New captures belong under `SwiftTests/Fixtures` with a focused test
and a note in this file. Scheduled validation should run the same catalog on
each supported macOS release.

## Current fixture catalog

These checked-in captures are the compatibility baseline. Their provenance is
the source command and hardware class recorded with each fixture; a live
machine-specific capture is not inferred from a fixture.

| Fixture | Hardware/source class | Expected normalized coverage | Focused tests |
| --- | --- | --- | --- |
| `ioport.plist` | Apple USB-C port-controller plane | receptacles, cable state, transports, PD and liquid fields | `PortPayloadTests`, `PresentationTests` |
| `usbplane.plist` | USB registry device tree | hubs, location IDs, parent/tier, descriptor basics | `USBRegistryTests` |
| `usb_interfaces.plist` | `IOUSBHostInterface` registry | interface class triples and endpoint counts | `USBInterfaceTests` |
| `tb_switch.plist` | Thunderbolt/USB4 switch plane | routers, ports, tunnels and raw link values | `ThunderboltFabricTests` |
| `hardware.json` / `power.json` | `system_profiler` hardware and power output | host model/chip and charging telemetry | `ParityTests`, `PortPayloadTests` |
| `usb_legacy_synthetic.json` | older/localized-shaped USB JSON | legacy fields and schema migration behavior | `SnapshotLoadingTests`, `USBRegistryTests` |

New hardware captures should add one row here, a provenance note, a focused
parser test, and a parity update only when the machine-readable schema
intentionally changes.
