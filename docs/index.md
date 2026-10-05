# usbscope — documentation

`usbscope` renders the USB subsystem of a Mac: receptacles, negotiated USB
modes, attached devices and the cable/port-controller facts macOS exposes. The
project is **Swift only** — one implementation, one test suite, one app. There is
no Python version, no virtualenv and no `uv`.

## Install & run

Requires macOS 14.4+ and Swift 6 (`swift build` and `swift test` are the whole
toolchain; Xcode or the command line tools provide them).

```console
swift build                   # build the CLI and the app
swift run usbscope            # overview
swift run usbscope ports -v   # port table with per-transport detail
swift run usbscope devices    # device tree only
swift run usbscope cables     # cable / e-marker / CC / liquid detection
swift run usbscope thunderbolt   # Thunderbolt / USB4 receptacles
swift run usbscope security   # per-device/port findings + USB mass storage
swift run usbscope --json     # JSON snapshot (schema below)
```

The built binaries live under `.build/debug/` (or `.build/release/`), so a
script can call `./.build/debug/usbscope` directly instead of going through
`swift run`.

| Option | Effect |
| --- | --- |
| `-v`, `--verbose` | add raw detail (location IDs, plug orientation, TRM state, per-transport rate/signaling/lanes, CC hash status, SOP revision, sources, controller detail) |
| `--json` | print the snapshot as JSON and exit (also as the `json` view) |
| `--progress` | name each source as it is read, on stderr, so a slow collect is not a silent wait (stdout stays clean) |
| `--no-color` | disable colours (also honoured when stdout is not a terminal) |
| `--watch seconds` | redraw in place every *seconds* until `Ctrl-C` — see [Live mode](#live-mode-and-the-event-stream) |
| `-h`, `--help` | print usage and exit |
| `--version` | print the version and exit |

Exit status: `0` success; `1` an unexpected failure (a report that cannot be
written, a baseline that cannot be saved); `2` a usage/parse error or a malformed
expectation; `3` `check`/`baseline` found a mismatch. `watch --events` runs until
interrupted.

## Live mode and the event stream

Two streaming entry points, one for humans and one for scripts.

**`usbscope --watch <seconds>`** redraws the selected view in place until `Ctrl-C`.
Each cycle collects a fresh snapshot and renders it — nothing is buffered across
frames, so what is on screen is always a real reading and never a mixture of two.
On a terminal it clears the screen and parks the cursor first; when stdout is a
pipe or a file the frames are appended instead, which is what makes
`make watch | grep -c 'usbscope — live'` a usable check. The interval is clamped
to a minimum of 0.2 s, and one `collect` costs about 1.3 s on a MacBook Pro
(`system_profiler` dominates), so the practical cadence is a little slower than
the number you pass.

**`usbscope watch --events`** prints one flushed JSON line per attach/detach so it
can be piped (see
[the four scriptable commands](#beyond-the-views-check-watch---events-baseline-report)).
It builds on `UsbHotplugWatcher`: it arms real IOKit notifications
(`kIOMatchedNotification` / `kIOTerminatedNotification` on `IOUSBHostDevice`) and
does nothing between edges. When IOKit cannot be armed, the watcher falls back to
comparing snapshots on a timer; `--interval S` sets that poll interval (default
2 s).

The app has its own take on this: `⌘R` plus an auto-refresh toggle and a
2/5/10/30 s interval menu.

## What each view shows

| View | Content |
| --- | --- |
| `overview` (default) | summary panel, port table, device tree, USB4 table |
| `ports` | port table + device tree: state, negotiated mode, transports, cable, notes |
| `devices` | bus → device tree with VID/PID, link mode, serial, port/transport mapping, and one line per interface descriptor (`if 0 · HID (3/1/1) · 1 endpoint(s)`) |
| `cables` | cable class (passive / e-marked / active / optical), CC authentication + hash status, SOP spec revision, LDCM liquid status, controller firmware; `-v` adds the port-controller USB mode plus a *Charging & adapter* panel |
| `thunderbolt` | Thunderbolt/USB4 receptacles: state, link speed, host adapter |
| `usb4` | the USB4 fabric as a tree: routers, their ports (with the raw link speed/width enumerations) and the PCIe/USB/DisplayPort tunnels on them |
| `security` | security findings per device/port (severity + short reason) plus the USB mass-storage inventory |

`-v/--verbose` adds raw detail (location IDs, plug orientation, TRM state,
per-transport rate/signaling/lanes, CC hash status, SOP revision, sources) and the
optional port-controller details (USB mode, USB-C pin assignment, power contract,
LDCM state). The summary panel then also carries the live `Charging`/`Power` rows
and `usbscope cables -v` adds the charging panel.

## Beyond the views: `check`, `watch --events`, `baseline`, `report`

Four commands that turn the inspector into something a script or a test rig can
use.

| Command | What it does |
| --- | --- |
| `usbscope check --expect …` | asserts facts about the current machine and sets the exit code — `0` every expectation holds, `3` one fails, `2` a malformed expectation. Forms: `device=<vid:pid\|name>`, `port=<name>`, `connected>=N`, `devices>=N`, `warning=0` |
| `usbscope watch --events [--interval S]` | one flushed JSON line per attach/detach (`kind`, `timestamp`, name, VID/PID, serial, location id, port) so it can be piped. Driven by IOKit notifications, falling back to a polling differ |
| `usbscope baseline save <file>` / `check <file>` | store a snapshot as *known good* and compare the live machine against it: appeared / disappeared / changed ports, exit `0` identical, `3` different, `2` unreadable |
| `usbscope report [--format md\|html] [--out file]` | a human-readable report (machine, ports, devices with class/tier, cables, power contract, security findings, warnings). Markdown by default; a self-contained styled HTML page with `--format html` |

```console
swift run usbscope check --expect 'connected>=1' --expect 'device=0x1050:0x0407'
swift run usbscope baseline save ~/known-good.json && swift run usbscope baseline check ~/known-good.json
swift run usbscope report --format html --out usbscope-report.html
./.build/debug/usbscope watch --events | jq -c .
```

## The macOS app

The same data as a native SwiftUI window (`usbscope-app`) — ten views in a
toolbar segmented switcher and via `⌘1`–`⌘9`, a live search field, filter presets,
grouping and a per-view column chooser:

![usbscope app](docs/screenshots/app-ports.png)

Three of the newer views, captured with `usbscope-app --snapshot` (no screen
recording permission is needed — the window is rendered offscreen):

| Security | USB4 fabric | Diff |
| --- | --- | --- |
| ![security tab](docs/screenshots/app-security.png) | ![USB4 tab](docs/screenshots/app-usb4.png) | ![diff tab](docs/screenshots/app-diff.png) |

The Diff tab above is compared against a snapshot of the *same machine* saved half
an hour earlier: the cable that was still on USB-C@1 then is gone, so it reports
one changed port. The Timeline tab fills up as the app runs (watts over time plus
the hotplug log); its screenshot in `docs/screenshots/app-timeline.png` is the
state before anything has been recorded. The CLI screenshots in the same folder
are the older illustrations and carry their own captions.

```console
swift run usbscope-app              # or: make swift-run-app
make swift-app-check                # headless: row count of every view, then exit
```

Views: **Ports** (state, negotiated mode, transports, cable, notes), **Cables**
(CC authentication, hash, PD spec revision, power in with the negotiated
contract, port-controller USB mode, liquid detection, controller firmware),
**Devices** (flat table with bus, port, transport, serial, macOS restriction),
**Thunderbolt** and **Power** (the live charging telemetry: adapter, input,
system load, battery).

| Feature | Behaviour |
| --- | --- |
| Tabs | Ten views in the toolbar/sidebar and via `⌘1`–`⌘9` plus the command palette: **Ports · Cables · Devices · Thunderbolt · Power · Timeline · Security · USB4 · Diff · Warnings** |
| Search | Toolbar field, live filter over every column (all terms must match) |
| Presets | Quick filters next to the search field: all / HID only / storage only / connected only |
| Sorting | Click a column header; a mode rank and a port number sort `USB 1.1` below `USB 3.2 Gen 2` and `@2` below `@10` |
| Grouping | Toolbar "Group by" for bus / class / speed |
| Columns | A per-view column chooser; the layout is remembered per view |
| Detail sheet | **Details** button / `⌘D` shows every field of the selected row (port, cable, device or charging metric) |
| Refresh | `⌘R`, plus an auto-refresh toggle and a 2/5/10/30 s interval menu |
| Timeline tab | Sparkline of the live charging watts over time plus the hotplug log (attach/detach with timestamps), newest first |
| Security tab | The `security` findings with a severity badge, the rule, the subject and the reason, the storage inventory, and the same honest-limits wording the CLI prints |
| USB4 tab | Routers → ports → tunnels from the USB4 switch, with the raw link speed/width enumerations shown verbatim |
| Diff tab | "Compare with…" loads a snapshot JSON (e.g. one written by `usbscope baseline save`) and shows appeared / disappeared / changed against the live machine |
| Storage | Mount point, read-only flag and an **Eject** button per USB storage device (disabled with a reason when it is not possible) |
| Changes | Rows that appeared, disappeared or changed colour green/red/orange after a refresh; the status line names them |
| Copy / export | `⌘C`/`⇧⌘C` (TSV), `⇧⌘J` (snapshot JSON) to the clipboard; `⌘S`/`⇧⌘S` write JSON/CSV through a save panel |
| Menu bar extra | `connected/ports` (plus `⚠` when a source warns), view switching, "Refresh now", a notifications switch and quit |
| Notifications | One banner per device that appeared or disappeared — only from a bundled run (macOS refuses the request from a plain process) |
| Preferences | `⌘,`: default view, interval, auto-refresh, notifications, appearance, language (DE/EN), grouping, and per-rule heuristic severity display — persisted in the `com.zopyx.usbscope` defaults domain |
| Status | Summary line (ports/connected/devices/cables) and a status bar with the read time, cadence, changes and warnings |
| Loading | three states — idle → loading → loaded. While a read is in flight the status line names the source it is on (`collecting Charging · 5/6`) next to a determinate bar, so the ~1.3 s a collect takes is not a silent wait |
| Screenshots | `usbscope-app --snapshot out.png [--view security]` renders the window offscreen and exits — no screen-recording permission needed; Timeline also exposes its measured values as an accessible text table |

`usbscope-app --print-rows` is the headless check of the data path (row count per
view), `--smoke` checks the bundled export, diagnostics, and watcher lifecycle,
and `--show-about` opens the About window straight away.

Run from the checkout the app calls `NSApplication.setActivationPolicy(.regular)`
to bring the window to the front; a real bundle gives it a Dock entry and a proper
menu bar.

**Notifications need the bundle.** macOS refuses — and in fact *aborts* — a
`UNUserNotificationCenter` call from a non-bundled process, and terminals export
their own `__CFBundleIdentifier`, so the app checks for *its own* bundle identifier
before touching the notification centre. A checkout run (`swift run usbscope-app`)
therefore keeps the status item but stays silent by design; install
`usbscope-swift.app` to get the banners.

## Columns of the port table

| Column | Meaning |
| --- | --- |
| Port | receptacle from the port controller, e.g. `USB-C@3` (`@N` is the hardware port number) |
| Type | `USB-C`, `MagSafe 3`, `HDMI`, `SD Card` |
| State | `ConnectionActive` reported by the port controller |
| Negotiated mode | link mode of the active USB transport, derived from the negotiated rate |
| Transports | `CC` (configuration channel), `USB2`, `USB3`, `DP` (DisplayPort alt mode), `SD`; `●` active, `○` idle |
| Cable | cable class; e-marked means the controller received a SOP e-marker response |
| Notes | attached device(s), DisplayPort alt mode, power in with the negotiated contract, liquid detection, accessory authorization, macOS restriction (TRM); `-v` adds the USB mode, pin assignment and LDCM state |

Mode labels are derived from the negotiated rate (`1.5 / 12 / 480 Mbit/s`,
`5 / 10 / 20 / 40 / 80 Gbit/s`). A device that negotiates 12 Mbit/s is
therefore reported as *USB 1.1 Full-Speed* even when it is plugged into a USB-C
port — the mode describes the link, not the connector.

## Data sources

| Source | Used for |
| --- | --- |
| `system_profiler SPUSBHostDataType -json` | bus tree, devices, link speed, VID/PID, serial (modern key names) |
| `system_profiler SPUSBDataType -json` | fallback for machines that only expose the legacy device list |
| `system_profiler SPThunderboltDataType -json` | Thunderbolt/USB4 receptacles, link status and cable capability |
| `ioreg -r -c IOThunderboltSwitch -a -l -w0` | USB4 fabric: routers (UID, router id, depth), switch ports (link speed/width, lane, credits) and the PCIe/USB/DisplayPort tunnel adapters |
| `system_profiler SPPowerDataType -json` | adapter watt, charger connected, charging state, state of charge |
| `ioreg -a -l -w0 -p IOPort` | port controller view: ports, transport states, cable/CC/SOP data, power contract, LDCM, TRM |
| `ioreg -a -l -w0 -p IOUSB` | USB device tree: descriptor basics (`bDeviceClass`/`SubClass`/`Protocol`, `bcdUSB`, `bMaxPacketSize0`, `bNumConfigurations`), enumeration speed code, device address, hub tier and parent hub |
| `IOUSBHostInterface` (in-process IOKit, `ioreg -a -c IOUSBHostInterface -r -l -w0` as the fallback) | the interface descriptors of every device: number, alternate setting, class triple, configuration value and endpoint count, joined to the device by `locationID` |
| `diskutil list -plist` / `diskutil info -plist <device>` | USB mass storage (security view): whole disks with `BusProtocol == USB`, capacity, read-only state and mount point |
| `ioreg -r -n AppleSmartBattery -a -l -w0` | live power telemetry: adapter input, system load, battery flow, adapter PD menu |

The `IOPort` plane is read **in-process** through IOKit by default
(`IORegistryReader`: `IOServiceGetMatchingServices` +
`IORegistryEntryCreateCFProperties` + `IORegistryEntryCreateCFProperty`, walking
`IORegistryEntryChildren`), and the `/usr/sbin/ioreg` subprocess is kept as a
**fallback**, used whenever the in-process read fails or reports no port.
`IORegSourceBackend` pins the choice; either path produces the same dictionary
the plist parser consumes, so the result is identical. See
[In-process registry reader](#in-process-registry-reader).

Both sources are optional at runtime: a failing source only adds a warning that
is rendered in a yellow *notes* panel (or in `warnings[]` of the JSON), it never
aborts the run. That holds for the two power sources too.

The device list is merged by `locationID`: `system_profiler` supplies the
vendor/product/serial identity and `ioreg` contributes the port, the transport
and the macOS restriction state. Devices that only the port controller reports
appear under the synthetic bus *"Port controller only (no bus entry)"*.

## Semantics and honest limits

* **Cable data** is what the port controller publishes. macOS exposes the cable
  class flags (`ActiveCable`, `OpticalCable`), the CC authentication/hash status
  and the `SOP` node of the power-delivery negotiation. Only the `SOP'`/`SOP''`
  ordered sets come from a cable *plug*, i.e. an e-marked cable — usbscope shows
  `e-marked` only when such a node is present and otherwise reports the cable as
  `unknown` instead of guessing. The full e-marker payload (vendor ID, current
  rating) is not public on macOS without private entitlements, so it is not
  invented here.
* **`plug orientation`** and the raw enumeration values from the controller are
  reported verbatim in `-v` mode instead of being mapped to "normal/flipped",
  because the numbering is not documented publicly.
* **The optional port-controller details are raw enumerations too.** The USB mode
  (`IOAccessoryUSBModeType`), the accessory mode, the power contract
  (`IOAccessoryPowerMode`, `IOAccessoryPowerCurrentLimits`), the
  `Pin Configuration` map and the LDCM state/measurement are shown as the
  controller reports them — `-v`, the detail sheet and the JSON snapshot carry
  them, the default table stays clean. Where the raw value is certain noise it is
  dropped instead of shown: an idle pin map (`pins:` lists only non-zero entries),
  an all-zero current-limit list and an `AccessoryMode` of `0`.
* **Device descriptors are device level; the interfaces come from the registry.**
  `ioreg -p IOUSB` publishes the device class triple, `bcdUSB`, the control
  endpoint packet size and the configuration count. The *interfaces* are separate
  `IOUSBHostInterface` objects in the registry (`ioreg -c IOUSBHostInterface -r`),
  which is readable without an entitlement: each carries its number, alternate
  setting, class triple, configuration and endpoint count, and they are attached to
  the device by `locationID`. A class of `0` at the device level is still reported
  as `per-interface`, but the interfaces behind it are listed. The endpoint
  descriptors themselves are published nowhere, so an interface is only known to
  have *n* endpoints. The `Tier` column is the hub depth (1 = directly on a
  controller) and `Parent hub` names the hub above a device.
* **`restricted by macOS`** mirrors the port controller's `TRM_TransportRestricted`
  flag (the "allow accessory to connect" prompt used from macOS 13 on).
* **Power has two different truths, and they are kept apart.** A port
  controller publishes the *contract* it negotiated (the winning
  `PowerSourceOption`, e.g. `20 V · 5 A · 100 W`) plus the full PD menu of the
  charger — that is a ceiling, not a measurement. The *live* numbers (adapter
  input, system load, battery flow) only exist system wide in the SMC, so they
  live in the `power` view / the charging panel and never pretend to belong to a
  single port. A cable that carries no power therefore cannot be singled out.
* **The power sources disagree, and that is shown as it is.** The adapter watt
  from System Information (`70 W`), the port contract from the controller
  (`20 V · 5 A · 100 W` in one capture) and the SMC's own adapter view
  (`AdapterVoltage`/`Current`) come from three places; they are never averaged
  into one number. macOS also reports the charging *state* twice: System
  Information can say "fully charged, not charging" while the SMC still lists
  `IsCharging` with a small battery current. usbscope takes the state from
  System Information and the measured flow from the SMC.
* **The contract and the menu are two different things.** The port controller
  publishes the *negotiated* option (the RDO result, marked `[*]` in the
  registry) and, next to it, the whole PDO menu the charger advertises — a
  ceiling, not a measurement. Each option carries its PDO type (`fixed`, or
  `adjustable` for a PPS/APDO) and the controller's option UUID, so the view can
  say "negotiated 20 V · 5 A · 100 W out of 4 fixed options, 5–20 V, up to
  100 W". The details sheet shows the menu summary as `PD menu`; the default
  tables stay clean.
* Thunderbolt link speed is the *cable capability* reported per receptacle, not
  the negotiated lane rate.
* **The receptacles and the fabric are two views of the same sockets, and they are
  never merged.** `system_profiler` describes the physical receptacle (status,
  cable capability); `ioreg -c IOThunderboltSwitch` describes the USB4 *topology*:
  the routers (`router_id`, `uid`, `depth`, `route_string`), the switch ports with
  their link facts and the PCIe/USB/DisplayPort tunnel adapters below them. The
  fabric lives in the JSON snapshot (`thunderbolt_fabric`); the terminal tables
  keep showing the receptacles.
* **The switch link facts are raw enumerations.** `Current`/`Target`/`Supported
  Link Speed` and `-Width`, the lane, the credits and the `Adapter Type` bitfield
  are published by the switch but their encoding is not public, so usbscope reports
  the integers verbatim plus the port `label` (e.g. `PCIe Adapter`) instead of
  inventing a Gbit/s number or a generation.
* **A tunnel adapter is not an established tunnel.** macOS lists one down-adapter
  port per tunneled protocol the router *can* carry, whether or not a device is
  attached, so usbscope reports the tunnel endpoints with their driver and never
  claims an active tunnel. A daisy-chained router appears as its own entry in
  `routers` with `depth` > 0; the host routers are the `depth` 0 entries.

## Security posture (`usbscope security`)

`usbscope security` runs a small, purely local analysis over the same snapshot
(no sudo, no private framework), printing the findings most severe first and the
USB mass-storage inventory below them. `usbscope security --json` emits the
findings and the storage as their own document (`kind: "security"`) — it never
changes the `schema_version: 1` snapshot document. The JSON also includes
`storage_status`, `storage_warnings`, and structured `storage_errors` when
`diskutil` is unavailable or returns malformed data, so an empty list is not
mistaken for a successful no-storage result.

| Severity | Rule | Fires when |
| --- | --- | --- |
| `warning` | `mass-storage` | the device reports USB base class 8 (mass storage) |
| `warning` | `hid-and-storage-on-port` | one receptacle carries both a class-3 and a class-8 device |
| `warning` | `hid-and-storage-on-device` | one device declares both HID and mass-storage interfaces — a filesystem and a keyboard at once |
| `attention` | `hid-without-serial` | a class-3 (HID) device has no serial number |
| `attention` | `restricted-by-macos` | the device was marked restricted by macOS (the port controller's TRM flag) |
| `attention` | `authorization` | a port's accessory authorization is neither `Not Required` nor `No Action` |
| `attention` | `restricted-transport` | an *active* transport of a port is restricted by macOS (TRM) |
| `attention` | `no-usb-data` | a device is attached but the controller reports no active USB2/USB3/USB4 transport |
| `info` | `composite-per-interface` | the device class is `0` (declared per interface) |
| `info` | `composite-iad` | the device reports the IAD composite triple `0xEF/2/1` |

The severity is a heuristic, not a verdict. The analysis is explicit about what
it cannot see:

* **The interface tree is read, the endpoint tree is not.** macOS publishes one
  `IOUSBHostInterface` object per interface in the registry — number, alternate
  setting, class triple, configuration and the endpoint *count* — and that needs
  no entitlement, so the rules below run against device-level *and* interface-level
  classes. What is still missing is the endpoints themselves: their descriptors
  (address, transfer type, packet size, interval) are published nowhere, so an
  interface is only known to have *n* endpoints, not which ones. A device that
  publishes no interface objects is described by its device-level class only, and
  the `composite-per-interface` / `composite-iad` note says so instead of guessing.
* **Composites are checked where they are declared.** Because the interfaces are
  known, a device that reports class `0` at the device level but carries a
  mass-storage interface *is* flagged as mass storage, and one that carries both
  HID and mass-storage interfaces is flagged by `hid-and-storage-on-device` — the
  bad-USB shape — instead of being listed as an unknown composite.
* **A missing serial is a missing report.** `hid-without-serial` fires when
  macOS did not report a serial number, not when the device provably has none.
* **Authorization and restriction are the controller's own strings and flags**
  (`UserAuthorizationStatusDescription`, `TRM_TransportRestricted`), shown
  verbatim; a restriction is only reported for a transport that carries traffic.
* **Storage covers whole disks only.** The inventory keeps disks whose
  `diskutil` `BusProtocol` is `USB`, with capacity and read-only state from
  `diskutil info`. A Mac without USB storage is normal — an empty inventory, not
  an error — and the filesystem contents and the encryption state are not
  inspected.

## JSON schema (`schema_version: 1`)

```json
{
  "schema_version": 1,
  "host": "…", "os_version": "…", "model": "MacBook Pro", "chip": "Apple M3 Pro",
  "seen_at": "2026-10-02T19:52:00",
  "summary": {"ports": 6, "connected_ports": 2, "devices": 1, "emarked_cables": 0},
  "ports": [{
    "description": "Port-USB-C@3", "name": "USB-C@3", "kind": "USB-C", "number": 3,
    "connected": true, "mode": "full_speed", "mode_label": "USB 1.1 Full-Speed · 12 Mbit/s",
    "power_in": [],
    "cable": {"attached": true, "kind": "unknown", "emarker": false, "active": false,
              "optical": false, "authentication": "Idle", "hash_status": "Not Set",
              "pd_spec_revision": null},
    "pin_configuration": {"rx1": 0, "rx2": 4, "tx1": 0, "tx2": 3, "sbu1": 0, "sbu2": 0},
    "usb_mode_type": 2, "accessory_mode": 0, "power_mode": 1, "active_power_mode": 1,
    "supported_power_modes": [1, 3], "power_current_limits": [0, 0, 0, 0, 0],
    "liquid_state": "Idle", "liquid_measurement": "No Error", "liquid_pin": "Reference",
    "liquid_mitigations": false, "liquid_override": false,
    "power_sources": [{"name": "USB-PD", "type": 2, "priority": 1000, "selected": true,
                       "winning": {"voltage_mv": 20000, "max_current_ma": 3000,
                                   "max_power_mw": 60000, "watts": 60.0},
                       "options": [{"voltage_mv": 5000, "max_current_ma": 3000,
                                    "max_power_mw": 15000, "watts": 15.0}]}],
    "transports": [{"kind": "USB2", "active": true, "rate": "12 Mbps (Full Speed)",
                    "speed_mbps": 12, "mode": "full_speed", "generation": "USB 2.0",
                    "signaling": null, "data_role": "Host", "lanes": null,
                    "restricted": false, "trm_state": "Limited",
                    "trm_profile": "Ask for New Accessories", "hash_status": "Cached"}],
    "devices": [{"name": "YubiKey OTP+FIDO+CCID", "id": "0x1050:0x0407", "mode": "full_speed"}]
  }],
  "buses": [{"name": "USB 3.1 Bus", "driver": "AppleT8122USBXHCI", "devices": []}],
  "thunderbolt": [{"bus": "thunderboltusb4_bus_0", "receptacle": 1, "status": null,
                   "speed": "Up to 40 Gb/s", "connected": false}],
  "thunderbolt_fabric": {"routers": [{
      "router_id": 0, "uid": 408840496304102592, "vendor_id": 1452, "vendor_name": "Apple Inc.",
      "device_model_name": "iOS", "device_model_id": 15, "device_model_revision": 1,
      "thunderbolt_version": 32, "depth": 0, "route_string": 0, "max_port_number": 7,
      "ports": [{"number": 1, "label": "Thunderbolt Port", "protocol": "thunderbolt",
                 "socket_id": "1", "adapter_type": 1, "current_link_speed": 8,
                 "target_link_speed": 12, "supported_link_speed": 12, "current_link_width": 1,
                 "target_link_width": 1, "supported_link_width": 2, "lane": 1, "dual_link_port": 2,
                 "link_bandwidth": 100, "max_credits": 174, "max_in_hop_id": 22,
                 "max_out_hop_id": 22, "upstream_port_number": null, "restricted": false}],
      "tunnels": [{"protocol": "pcie", "label": "PCIe Adapter", "port_number": 3,
                   "adapter_type": 1048833,
                   "driver": "com.apple.driver.AppleThunderboltPCIDownAdapter",
                   "driver_class": "AppleThunderboltPCIDownAdapterType5",
                   "device_id": "0x00002000&0x0000ff00"}]}]},
  "charging": {"connected": true, "charging": true, "fully_charged": false,
               "state_of_charge": 100, "time_remaining_minutes": 14,
               "system_power_in_mw": 27575, "system_voltage_in_mv": 19478,
               "system_current_in_ma": 1417, "system_load_mw": 16084,
               "battery_power_mw": 11491, "battery_voltage_mv": 12955,
               "battery_current_ma": 887, "adapter_power_mw": 70000,
               "adapter_voltage_mv": 20000, "adapter_current_ma": 3500,
               "adapter_efficiency_loss_mw": 679, "not_charging_reason": 0,
               "slow_charging_reason": 0, "thermally_limited_seconds": 0},
  "warnings": []
}
```

The schema is defined once, in `Sources/UsbScopeCore/Serialize.swift`; the
changelog is [schema-changelog.md](schema-changelog.md).

## Package layout

The whole project is this one Swift package (`Package.swift`,
`swift-tools-version: 6.0`, macOS 14.4+).

| Part | Path |
| --- | --- |
| Core library `UsbScopeCore` | `Sources/UsbScopeCore/` — model, `ioreg`, `system_profiler`, charging, snapshot, JSON serialiser, formatting, the hotplug watcher, the event log and history |
| Presentation library `UsbScopeUI` | `Sources/UsbScopeUI/` — table rows, cell styles, `Highlight`, detail pairs, TSV/CSV export, filter presets, grouping, diff presentation (no SwiftUI, so it is unit-testable headless) |
| CLI executable `usbscope` | `Sources/usbscope/main.swift` |
| SwiftUI app `usbscope-app` | `Sources/usbscope-app/` — the ten views on top of `UsbScopeUI` |
| Test suite | `SwiftTests/` |
| Fixtures | `SwiftTests/Fixtures/` — 14 real and synthetic payloads |
| Golden | `SwiftTests/Golden/snapshot.json` — a frozen regression reference (below) |

## Makefile

`make` (or `make help`) lists every task grouped by section; the `##` comment next
to a target is its description. There is no Python environment to sync — every
target runs `swift` or a shell command.

| Target | Does |
| --- | --- |
| `make help` | list the targets |
| `make doctor` | checks the tools this repo needs (swift, codesign, plutil, hdiutil, the icon) |
| `make env` | print the Swift and Xcode toolchain versions |
| `make build` / `make test` | `swift build` resp. `swift test` |
| `make check` | all gates (build + tests) — the CI equivalent |
| `make check-all` | alias for `check` |
| `make swift` / `make swift-build` / `make swift-test` | build and test the package |
| `make run` | run the CLI overview |
| `make watch` | run the CLI with live refresh every 2 s (`--watch 2`) |
| `make swift-run-app` | run the SwiftUI app (`usbscope-app`) |
| `make swift-app-check` | headless self test of the app's data path (row count per view) |
| `make swift-app-bundle` | build `dist/usbscope-swift.app` (release, ad-hoc signed, verified) |
| `make swift-app-dmg` | pack the app into a compressed, read-only DMG (`hdiutil`, mode-tagged) |
| `make snapshot` | render the app window to `docs/screenshots/app-<view>.png` (offscreen) |
| `make checksums` | verify `dist/SHA256SUMS`, written over the tarball and the DMG |
| `make man` / `make completions` | install the CLI manual page / the zsh + bash completions into `~` (no sudo) |
| `make version` | print the package version |
| `make clean` / `make distclean` | build output / plus the package caches |

Variables: `CONFIG=debug|release` selects the build configuration,
`VERSION` is read from `Sources/usbscope/main.swift`.

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and on every pull request,
on an Apple-Silicon runner (`macos-14`):

| Step | Command |
| --- | --- |
| Toolchain | `swift --version`, `xcodebuild -version` |
| Build | `swift build` |
| Test | `swift test` |
| Bundle (main only) | `scripts/build-swift-app.sh`, uploaded as a 7-day artifact |

There is no Python environment to sync and no virtualenv to cache. Tests that
need the live IORegistry (the backend comparison, the timing comparison) skip
themselves on a runner where it cannot be read. The bundle step is guarded by
`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`, and
`concurrency` cancels a superseded run for the same ref.

Signing for real distribution (Developer ID, `notarytool`, `stapler`, universal2,
Homebrew cask) is documented — including what is still *not* done — in
[distribution.md](distribution.md). The Mac App Store path (sandbox entitlements,
Apple Distribution signing, `productbuild`, App Store Connect metadata and the
open sandbox question) is in [app-store.md](app-store.md).

## Building the app bundle

`scripts/build-swift-app.sh` (or `make swift-app-bundle`) compiles the app with
`swift build -c release --product usbscope-app`, assembles
`dist/usbscope-swift.app` and fails loudly instead of leaving a half-built
bundle:

1. **Compile**: `swift build -c release --product usbscope-app` (or `--debug`),
   then `swift build --show-bin-path` to locate the executable.
2. **Assemble**: copies the binary to `Contents/MacOS/usbscope-app`, the icon to
   `Contents/Resources/` (when `assets/icon/usbscope.icns` exists), and writes
   `Contents/Info.plist` with `CFBundleIdentifier com.zopyx.usbscope`, the package
   version as `CFBundleShortVersionString`/`CFBundleVersion`,
   `LSMinimumSystemVersion 14.4`, `NSHighResolutionCapable`,
   `LSApplicationCategoryType public.app-category.utilities` and
   `ITSAppUsesNonExemptEncryption = false`. The plist is validated with
   `plutil -lint`.
3. **Sign**: `codesign --force --deep --sign - --identifier com.zopyx.usbscope`
   (ad hoc), followed by `codesign --verify`. The verification is not optional.
4. **Self test**: the *bundled* app is executed — `--version` must print,
   `--smoke` exercises first-read, atomic exports, diagnostics, and watcher
   lifecycle, and `--print-rows` exercises the data path when a window server
   is available.

The script prints every command it runs. Options: `--configuration release|debug`,
`--debug`, `--name NAME`, `--no-icon`, `--no-sign`, `--no-verify`, `--no-archive`,
`--universal` (build arm64 + x86_64 as a fat Mach-O; native-only otherwise).

The result is a single Mach-O with **no embedded frameworks** (macOS 14+ ships the
Swift runtime), so the whole bundle is about 3 MiB; `--universal` makes it a fat
arm64 + x86_64 Mach-O instead. The signature is ad hoc only either way. On top of
the bundle the script writes the tarball, and `scripts/build-swift-dmg.sh` (`make
swift-app-dmg`) packs the same bundle into a compressed DMG — both ad hoc only.
What a real release still needs (Developer ID, hardened runtime, `notarytool`,
`stapler`, notarisation) is in [distribution.md](distribution.md).

`usbscope-app --snapshot out.png [--view cables] [--baseline file.json]` renders
the **whole window** offscreen (no screen, no screen-recording permission) and
exits — the PNG is taken from the window frame, so it contains the real titlebar
and toolbar. `make snapshot` regenerates `docs/screenshots/app-*.png`. One
limitation remains, and it only affects captures: forcing an appearance
(`NSAppearance`) makes the layer-backed labels come out blank, so captures follow
the system appearance, which is what the window shows anyway.

For reproducible visual review, pass `--fixture SwiftTests/Golden/snapshot.json`
to render from the checked-in normalized capture instead of live host data;
`make swift-app-fixture-smoke` exercises all ten views from that stable input,
and `make swift-app-visual-check` compares them with the reviewed PNG baselines
under `docs/screenshots/fixture-baselines/`.

## Prebuilt binary (CLI)

**No prebuilt binary is published.** There is no signed or notarised release, and
no release pipeline; the former Python/PyInstaller artifacts are gone with the
Python implementation. Build the CLI yourself:

```console
swift build -c release
./.build/release/usbscope --version
```

There is no *published* release, but the build does produce hand-out artifacts: a
tarball and a DMG, both checksummed in `dist/SHA256SUMS` and both ad hoc signed
only. What a real release still needs — Developer ID, hardened runtime,
notarisation, stapling and a signed, notarised DMG — is in
[distribution.md](distribution.md).

## Screenshots

`docs/screenshots/` holds the images used by the README and this document:

* The **app window** shots (`app-ports.png`, `app-cables.png`, …,
  `asc-1280x800.png`, `asc-1440x900.png`) come from `make snapshot`, i.e. the
  Swift app's `--snapshot` mode.
* The **CLI** shots (`overview.svg/png`, `ports`, `cables`, `devices`) are static
  captures kept as illustrations. They were rendered by the former Python
  console renderer, which no longer exists; the Swift CLI has its own small
  renderer and does not export SVG, so these files cannot be regenerated from
  this checkout today.

The committed captures use a masked host name (`mac`) so the header does not
leak the machine name; the device inventory and the model/chip line are left as
they are — generic hardware facts, not identifiers.

## Development

```console
swift build            # build everything
swift test             # the suite
make check             # build + tests, the CI equivalent
make swift-app-check   # headless row count of every app view
make swift-app-bundle  # assemble + sign + verify dist/usbscope-swift.app
```

`SwiftTests/` holds the suite. `SwiftTests/Fixtures/` holds real payloads captured
on a MacBook Pro (macOS 27.0.1) plus synthetic payloads for key styles no longer
produced by this OS (their names say so); the fixture README lists each file and
its origin. Parsers are tested against the fixtures, and the presentation layer
(table rows, sort ranks, diffing) is tested headless because `UsbScopeUI` does not
import SwiftUI.

**The golden is frozen.** `SwiftTests/Golden/snapshot.json` was produced once by
the former Python serialiser, and that generator is gone with the Python
implementation. It can no longer be regenerated from a second implementation — it
is read-only history that pins the JSON shape, and `ParityTests` compares the
Swift-built snapshot against it. Regenerating it would mean hand-editing or
re-deriving the reference; do not expect a `make` target for it.

Two macOS-specific pitfalls are covered by tests because they are easy to
reintroduce:

* `NSNumber` bridges to `Bool` for the integers `0` and `1` on Darwin, so
  `value is Bool` is not a boolean test — the adapters use `PlistValue.isBool`
  (`CFGetTypeID`), otherwise a pin assignment of `0` or a port number of `1`
  would silently vanish from the JSON.
* `ProcessInfo.processInfo.hostName` returns the Bonjour local name, whereas
  `gethostname(3)` is the plain host name; the Swift side calls `gethostname`.

### In-process registry reader (Plan B)

`Sources/UsbScopeCore/IORegistryReader.swift` reads the `IOPort` registry plane
through IOKit (`IOServiceGetMatchingServices` +
`IORegistryEntryCreateCFProperties` + `IORegistryEntryCreateCFProperty` walking
`IORegistryEntryChildren`) instead of spawning `/usr/sbin/ioreg`. It returns the
same dictionary shape the plist parser consumes, so `IOReg.parsePorts` is
unchanged; `IORegistryReader.runner()` wraps it as a `Runner`, which makes
`IoregSource(runner: IORegistryReader.runner())` a drop-in replacement for the
subprocess source. This is the sandbox answer from
[app-store.md](app-store.md) (Plan B) implemented for the core. On the machine
the fixtures were captured on the in-process tree parses to identical `Port`
values (verified against `ioreg -p IOPort`);
`SwiftTests/IORegistryReaderTests` skips the live assertions with `XCTSkip` where
the registry cannot be read.

Whether IOKit can read that plane **inside a real App Store sandbox remains
unverified** — that needs an Apple-issued signature and provisioning profile, not
an ad-hoc one (see [app-store.md](app-store.md)).

### Manual page and shell completions

```console
man ./docs/man/usbscope.1        # preview the manual page
make man                         # install it into ~/.local/share/man/man1
make completions                 # install the zsh + bash completions
```

`docs/man/usbscope.1` documents the CLI views, options, exit status and data
sources; `scripts/completions/_usbscope` (zsh) and
`scripts/completions/usbscope.bash` (bash) complete the same interface. Install
instructions are in [man/README.md](man/README.md).

### Hotplug events, event log and history

`usbscope-app` watches for USB hotplug **event-driven**, not by polling: it arms
`IOServiceAddMatchingNotification` for `kIOMatchedNotification` and
`kIOTerminatedNotification` on the `IOUSBHostDevice` class and does nothing
between edges (`UsbScopeCore.UsbHotplugWatcher`). The identity of an edge is
resolved by diffing one fresh snapshot against the previous one, because a
terminating device no longer reliably exposes its properties — so the event
carries the same `deviceKey` the table rows use. When IOKit cannot be armed (the
App Store sandbox), the watcher falls back to comparing snapshots on a
`DispatchSourceTimer`; `isEventDriven` and `status` say which path is active.

Every attach/detach is appended to
`~/Library/Application Support/usbscope/events.jsonl` as one JSON object per line
(ISO-8601 `seen_at`, the `deviceKey` as `key`) — append-only, never rewritten. The
app also keeps the last 240 snapshots in memory (`SnapshotHistory`), each with its
timestamp and the delta to its predecessor, and projects their charging telemetry
onto a `powerTimeline()` of watts (`system_power_in_mw`, the measured input).
