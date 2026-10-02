# Test fixtures

| File | Origin |
| --- | --- |
| `usbhost.json` | real capture: `system_profiler SPUSBHostDataType -json` on a MacBook Pro (Mac15,6), macOS 27.0.1, with one YubiKey attached |
| `usb_legacy_empty.json` | real capture: `system_profiler SPUSBDataType -json` on the same machine — the legacy data type reports nothing there, which is exactly why the tool prefers `SPUSBHostDataType` |
| `thunderbolt.json` | real capture: `system_profiler SPThunderboltDataType -json` (3 USB4 receptacles) |
| `hardware.json` | real capture: `system_profiler SPHardwareDataType -json`, reduced to the header fields |
| `ioport.plist` | real capture: `ioreg -a -l -w0 -p IOPort`, with the byte buffers and the `IOKitDiagnostics` blob pruned so the fixture stays reviewable |
| `usb_legacy_synthetic.json` | **synthetic**: hand-written payload using the legacy `SPUSBDataType` key names (`vendor_id`, `device_speed`, …). This macOS no longer produces that shape, so the fallback parser is pinned with a made-up payload instead of leaving it untested |

Do not add made-up values to the real captures; add a new `*_synthetic` file instead.
