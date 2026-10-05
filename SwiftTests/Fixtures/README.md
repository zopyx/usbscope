# Test fixtures

| File | Origin |
| --- | --- |
| `usbhost.json` | real capture: `system_profiler SPUSBHostDataType -json` on a MacBook Pro (Mac15,6), macOS 27.0.1, with one YubiKey attached |
| `usb_legacy_empty.json` | real capture: `system_profiler SPUSBDataType -json` on the same machine — the legacy data type reports nothing there, which is exactly why the tool prefers `SPUSBHostDataType` |
| `thunderbolt.json` | real capture: `system_profiler SPThunderboltDataType -json` (3 USB4 receptacles) |
| `tb_switch.plist` | real capture: `ioreg -r -c IOThunderboltSwitch -a -l -w0` (3 host routers, 6 ports and 4 tunnel adapters each), with the `DROM` blobs, the power-management dicts and the registry plumbing pruned so the link facts stay reviewable |
| `hardware.json` | real capture: `system_profiler SPHardwareDataType -json`, reduced to the header fields |
| `ioport.plist` | real capture: `ioreg -a -l -w0 -p IOPort`, with the byte buffers and the `IOKitDiagnostics` blob pruned so the fixture stays reviewable (captured with a 100 W charger attached) |
| `usbplane.plist` | real capture: `ioreg -a -l -w0 -p IOUSB`, pruned to the USB subtree (controllers + `IOUSBHostDevice`) and the verbose driver/power blobs so the descriptor facts stay reviewable |
| `usbplane_hub_synthetic.plist` | **synthetic**: a controller → USB3 hub → keyboard + flash drive chain. No hub was attached to the capture machine, so the tier/parent logic and the class decoder are pinned with a made-up tree |
| `tb_switch_synthetic.plist` | **synthetic**: a daisy-chained USB4 fabric — a downstream router hanging below port 2 of the host router — plus a TRM-restricted port, an unknown adapter label and a port whose link facts are missing. This machine has no daisy-chained device, so the depth/route-string walk and the unknown-protocol path are pinned with a made-up tree |
| `power.json` | real capture: `system_profiler SPPowerDataType -json`, reduced to the two entries the parser reads (`spbattery_information`, `sppower_ac_charger_information`) |
| `battery.plist` | real capture: `ioreg -r -n AppleSmartBattery -a -l -w0`, reduced to the parsed keys (no serials, no battery model block, no `IOReportLegend` blobs) |
| `usb_legacy_synthetic.json` | **synthetic**: hand-written payload using the legacy `SPUSBDataType` key names (`vendor_id`, `device_speed`, …). This macOS no longer produces that shape, so the fallback parser is pinned with a made-up payload instead of leaving it untested |
| `usb_interfaces.plist` | real capture: `ioreg -a -c IOUSBHostInterface -r -l -w0` for the device in `usbplane.plist` (the composite keypad: two HID interfaces and one smart-card interface). Pruned from 696 KB to 3 KB — the raw dump carries `IORegistryEntryChildren` and the whole HID subtree, and the parser reads none of it |

Do not add made-up values to the real captures; add a new `*_synthetic` file instead.

The captures come from the same MacBook Pro but from different sessions: `ioport.plist` was
taken with a 100 W charger (20 V · 5 A), the two power fixtures with a 70 W adapter. That is
why the port contract and the adapter watt differ in the suite — both are real, they are just
not from the same minute.
