# usbscope — documentation

`usbscope` renders the USB subsystem of a Mac: receptacles, negotiated USB
modes, attached devices and the cable/port-controller facts macOS exposes.

## Install & run

```console
uv sync                       # create the venv (Python 3.14+)
uv tool install .             # optional: put `usbscope` on your PATH
uv run usbscope               # overview
uv run usbscope --watch 2     # refresh every 2 s (Ctrl-C quits)
uv run usbscope ports -v      # port table with per-transport detail
uv run usbscope devices       # device tree only
uv run usbscope cables        # cable / e-marker / CC / liquid detection
uv run usbscope thunderbolt   # Thunderbolt / USB4 receptacles
uv run usbscope security      # per-device/port findings + USB mass storage
uv run usbscope --json        # JSON snapshot (schema below)
```

Exit codes: `0` success, `1` unexpected failure, `130`/`0` on Ctrl-C.

## Live mode (`--watch`)

`usbscope --watch 2` refreshes in place on the terminal's alternate screen
(`rich.live.Live`), so only the changed lines are repainted — no clear/redraw
flicker. The refresh counter sits in the header, tall content is cropped to the
window, and the previous screen is restored on Ctrl-C (and on `SIGTERM`, so the
terminal is never left in the alternate buffer). The sleep is shortened by the
collection time to keep the cadence even. `--watch` combined with `--json`/`json`
prints one snapshot instead, because JSON in a live loop makes no sense.

## What each view shows

| View | Content |
| --- | --- |
| `overview` (default) | summary panel, port table, device tree, USB4 table |
| `ports` | port table + device tree: state, negotiated mode, transports, cable, notes |
| `devices` | bus → device tree with VID/PID, link mode, serial, port/transport mapping |
| `cables` | cable class (passive / e-marked / active / optical), CC authentication + hash status, SOP spec revision, LDCM liquid status, controller firmware; `-v` adds the port-controller USB mode plus a *Charging & adapter* panel |
| `thunderbolt` | Thunderbolt/USB4 receptacles: state, link speed, host adapter |
| `security` | security findings per device/port (severity + short reason) plus the USB mass-storage inventory |

`-v/--verbose` adds raw detail (location IDs, plug orientation, TRM state,
per-transport rate/signaling/lanes, CC hash status, SOP revision, sources) and the
optional port-controller details (USB mode, USB-C pin assignment, power contract,
LDCM state). The summary panel then also carries the live `Charging`/`Power` rows
and `usbscope cables -v` adds the charging panel.

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
| `diskutil list -plist` / `diskutil info -plist <device>` | USB mass storage (security view): whole disks with `BusProtocol == USB`, capacity, read-only state and mount point |
| `ioreg -r -n AppleSmartBattery -a -l -w0` | live power telemetry: adapter input, system load, battery flow, adapter PD menu |

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
  controller reports them — `-v`, the detail popover and the JSON snapshot carry
  them, the default table stays clean. Where the raw value is certain noise it is
  dropped instead of shown: an idle pin map (`pins:` lists only non-zero entries),
  an all-zero current-limit list and an `AccessoryMode` of `0`.
* **Device descriptors are device level only.** `ioreg -p IOUSB` publishes the
  device class triple, `bcdUSB`, the control endpoint packet size and the
  configuration count. The interface/endpoint descriptor tree needs an
  `IOUSBHostDevice` user client, so a class of `0` (class declared per interface)
  is reported as `per-interface` instead of guessed. The `Tier` column is the hub
  depth (1 = directly on a controller) and `Parent hub` names the hub above a
  device.
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
changes the `schema_version: 1` snapshot document.

| Severity | Rule | Fires when |
| --- | --- | --- |
| `warning` | `mass-storage` | the device reports USB base class 8 (mass storage) |
| `warning` | `hid-and-storage-on-port` | one receptacle carries both a class-3 and a class-8 device |
| `attention` | `hid-without-serial` | a class-3 (HID) device has no serial number |
| `attention` | `restricted-by-macos` | the device was marked restricted by macOS (the port controller's TRM flag) |
| `attention` | `authorization` | a port's accessory authorization is neither `Not Required` nor `No Action` |
| `attention` | `restricted-transport` | an *active* transport of a port is restricted by macOS (TRM) |
| `attention` | `no-usb-data` | a device is attached but the controller reports no active USB2/USB3/USB4 transport |
| `info` | `composite-per-interface` | the device class is `0` (declared per interface) |
| `info` | `composite-iad` | the device reports the IAD composite triple `0xEF/2/1` |

The severity is a heuristic, not a verdict. The analysis is explicit about what
it cannot see:

* **A composite device's interfaces are not exposed.** macOS publishes the
  device-level class triple only; the interface/endpoint tree needs an
  `IOUSBHostDevice` user client. A class of `0` is therefore reported as
  `composite-per-interface` (and `0xEF/2/1` as `composite-iad`) and the view
  states that the contained functions — the HID + mass-storage mix of a bad-USB
  stick, for instance — **cannot be confirmed here instead of being guessed**.
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

## Makefile

`make` (or `make help`) lists every task grouped by section; the `##` comment next
to a target is its description. Everything runs through `uv`, so the pinned Python
3.14 and the locked dependencies are always used.

| Target | Does |
| --- | --- |
| `make doctor` | checks the tools this repo needs (uv, PyObjC, librsvg, codesign, hdiutil) |
| `make sync` | environment incl. the `macapp` extra (PyObjC) |
| `make format` / `make lint` | `ruff format` + `--fix` resp. `ruff format --check`, `ruff check`, `ty check` |
| `make test` / `make coverage` | `pytest` resp. pytest with a coverage report (`pytest-cov` is fetched on demand) |
| `make check` | all gates, i.e. lint + test — the CI equivalent |
| `make check-all` | `check` plus the Swift port (`swift test`) |
| `make run` / `make watch` / `make run-app` | CLI overview, CLI with live refresh, native app |
| `make snapshot` | app window → `docs/screenshots/app-<view>.png` (offscreen, no permissions needed) |
| `make refresh-screenshots` | CLI screenshots (SVG + PNG, host name masked) |
| `make screenshots` | both of the above |
| `make binary` | standalone CLI binary → `dist/` |
| `make icon` | regenerates `assets/icon/usbscope.icns` from the SVG |
| `make app-bundle` (alias `make app`) | icon + `usbscope.app` + styled DMG → `dist/` |
| `make dmg` | rebuilds only the DMG for an existing `dist/usbscope.app` |
| `make artifacts` | gates + CLI binary + app: the full release build |
| `make ci` | alias for `check` — what `.github/workflows/ci.yml` runs |
| `make mas-pkg` | signs with the sandbox entitlements and builds the App Store `.pkg` |
| `make mas-pkg-dry` | prints those commands without running them (no certificates needed) |
| `make checksums` | verifies `dist/SHA256SUMS` and `dist/SHA256SUMS-app` |
| `make install` | `uv tool install '.[macapp]'` (CLI + `usbscope-app` on the PATH) |
| `make swift` | builds and tests the Swift port (`swift build` + `swift test`) |
| `make swift-golden` | regenerates `SwiftTests/Golden/snapshot.json` from the fixtures (Python side) |
| `make swift-run-app` | runs the SwiftUI app (`usbscope-app`) |
| `make swift-app-check` | headless self test of the app's data path (row count per view) |
| `make clean` / `make distclean` | build output / plus the virtualenv |

Variables: `SHOT_HOST=<name> make refresh-screenshots` sets the host name shown in
the captures (default `mac`). On macOS two details matter: `make` is the old GNU
make 3.81 (no modern functions in the file), and the shell already exports a `HOST`
variable — which is why the screenshot variable is called `SHOT_HOST`.

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and on every pull request,
on an Apple-Silicon runner (`macos-14`), and mirrors what `make check` does:

| Step | Command |
| --- | --- |
| Environment | `uv sync --extra macapp` (the UI tests need PyObjC) |
| Gate 1–4 | `uv run ruff format --check`, `uv run ruff check`, `uv run ty check`, `uv run pytest -q` — one step each, so a failure names the gate |
| Build (main only) | `scripts/build_binary.py` and `scripts/build_app.py --no-dmg`, uploaded as a 7-day artifact |

The build steps are guarded by
`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`: PyInstaller
downloads a toolchain and produces multi-megabyte artifacts that a pull request
should not pay for. `concurrency` cancels a superseded run for the same ref.

Signing for real distribution (Developer ID, `notarytool`, `stapler`, universal2,
Homebrew cask) is documented — including what is still *not* done — in
[distribution.md](distribution.md). The Mac App Store path (sandbox entitlements,
Apple Distribution signing, `productbuild`, App Store Connect metadata and the open
sandbox question) is in [app-store.md](app-store.md); `make mas-pkg` builds the
installer package, `make mas-pkg-dry` shows the commands without needing certificates.

## The macOS app

The same data as a native Cocoa app (`usbscope-app`) — a real `NSWindow` with an
`NSToolbar`, a view based `NSTableView`, `⌘R`, an auto-refresh timer, a menu bar
extra and an Info.plist bundle you can drop into `/Applications`:

![usbscope app](docs/screenshots/app-ports.png)

```console
$ usbscope-app                    # from a checkout (needs the macapp extra)
$ open ~/src/usbscope/dist/usbscope.app   # or the built bundle / the release DMG
```

Views: **Ports** (state, negotiated mode, transports, cable, notes), **Cables**
(CC authentication, hash, PD spec revision, power in with the negotiated contract,
port-controller USB mode, liquid detection, controller firmware), **Devices**
(flat table with bus, port, transport, serial, macOS restriction), **Thunderbolt**
and **Power** (the live charging telemetry: adapter, input, system load, battery).

| Feature | Behaviour |
| --- | --- |
| Views | Segmented switcher (Ports · Cables · Devices · Thunderbolt · Power) in the toolbar, plus `⌘1`–`⌘5` and the status item menu |
| Search | Toolbar search field (`⌘F`), live filter over every column; the filter survives a view switch |
| Sorting | Click a column header to sort, click again to reverse. Sorting uses a hidden rank where the text would sort wrong (`USB 1.1` before `USB 3.2 Gen 2`, `@2` before `@10`) |
| Toolbar buttons | **Copy ▾** (selected rows, whole table, details, snapshot as JSON), **Export ▾** (CSV, JSON), **Refresh**, **Details** (popover for the selection), **Auto-refresh** + interval — every one of them the same action as its menu entry |
| Refresh that does not disturb | Selection (tracked by row key) and scroll position survive every reload, sort and filter |
| Change highlighting | Devices that appeared turn green, disappeared red, a changed port yellow — for 1.6 s after a read, plus a `changed: …` note in the status line |
| Clipboard | `⌘C` copies the selected rows as TSV, `⇧⌘C` the whole table, `⌘D` the detail pairs, “Copy as JSON” the raw snapshot; right click and the **Copy ▾** button have the same actions |
| Detail popover | Double click a row (or the **Details** button) for every field of that port/cable/device, including what the columns truncate and the optional controller details (USB mode, pin assignment, power contract, LDCM); the list scrolls when it is longer than the popover |
| Export | `File ▸ Export JSON…` (`⌘S`) / `Export CSV…` (`⇧⌘S`), toolbar **Export ▾**, and the same entries in the table's context menu |
| Tooltips | Every row, not only devices, carries its full detail list |
| Status item | Menu bar extra with `connected/ports` (plus `⚠` when a source warns), the full summary as tooltip, view switching, “Refresh now”, a notifications switch and quit |
| Notifications | One banner per device that appeared or disappeared — only from the bundled app (see below) |
| Remembered | View, cadence, sort state, column widths, window frame and the notification switch, in `~/Library/Preferences/com.zopyx.usbscope.plist` |
| Feinschliff | Alternating row colours, right aligned monospaced digits, self explaining empty states, About panel, Help ▸ Documentation |

**Notifications need the bundle.** macOS refuses — and in fact *aborts* — a
`UNUserNotificationCenter` call from a non-bundled process, and terminals export
their own `__CFBundleIdentifier`, so the app checks for *its own* bundle identifier
before touching the notification centre. A check-out run (`uv run usbscope-app`)
therefore keeps the status item but stays silent by design; install
`usbscope.app` to get the banners.

```console
$ uv run --extra macapp usbscope-app          # run from the checkout
$ make run-app                                # same, via make
$ make icon                                   # regenerate assets/icon/usbscope.icns
$ make app-bundle                             # build + verify + styled DMG into dist/
```

### Building the bundle

`make app-bundle` (or `uv run python scripts/build_app.py`) runs five steps and
fails loudly at each one instead of leaving a broken artifact:

1. **Icon**: the `icon` target renders `assets/icon/usbscope.svg` through
   `rsvg-convert` into an `.iconset` and builds `assets/icon/usbscope.icns`
   (`iconutil`), which PyInstaller embeds (`--icon`, `--no-icon` to skip).
2. **PyInstaller** (`--windowed --target-architecture arm64`) collects Python, Rich
   and PyObjC plus a generated entry point into `dist/usbscope.app`. Only `uv` is
   required — PyInstaller and PyObjC are fetched on demand; `codesign` and
   `hdiutil` ship with macOS.
3. **Info.plist** is rewritten with `CFBundleIdentifier com.zopyx.usbscope`, the
   package version, `CFBundleIconFile`, `LSMinimumSystemVersion 13.0` and
   `NSHighResolutionCapable`.
4. **Signing**: `codesign --deep --force --sign - --identifier com.zopyx.usbscope`
   (ad hoc), followed by `codesign --verify`.
5. **Self test**: the *bundled* app is executed —
   `dist/usbscope.app/Contents/MacOS/usbscope --snapshot … --view ports` — and the
   resulting PNG is checked. A windowed app still takes argv, which is how the build
   proves the artifact works before packaging it.

The DMG then comes from `scripts/make_dmg.py`: it stages the app next to an
`/Applications` symlink, generates/uses `assets/dmg/background.png`, applies the
Finder layout (icon view, window 600×400, icon size 128, icon positions,
background picture) through `osascript`, converts to `UDZO` and **mounts the result
read-only to verify** (app present, symlink resolves, bundled binary runs,
signature valid, background in place). A Finder/automation failure is reported as
`layout: skipped (…)` and does not fail the build.

| Artifact | Content |
| --- | --- |
| `dist/usbscope.app` | the bundle with `usbscope.icns` (drag into `/Applications`) |
| `dist/usbscope-0.2.0-macos-arm64.dmg` | styled disk image (~10.5 MiB) with Applications symlink |
| `dist/SHA256SUMS-app` | SHA-256 of the DMG |
| `dist/usbscope-<version>-macos-arm64[.tar.gz]` | standalone CLI binary (12.7 MiB) |
| `dist/SHA256SUMS` | SHA-256 of both CLI artifacts |

Install and check the built artifacts:

```console
make checksums                                            # both checksum files
open dist/usbscope-0.2.0-macos-arm64.dmg                   # drag the app onto Applications
hdiutil attach -nobrowse -readonly dist/usbscope-0.2.0-macos-arm64.dmg   # inspect it
/Volumes/usbscope/usbscope.app/Contents/MacOS/usbscope --version
```

`usbscope-app --snapshot out.png [--view cables]` renders the **whole window** — the
PNG is taken from the theme frame, so it contains the real titlebar and toolbar
(`make snapshot` regenerates `docs/screenshots/app-*.png`). `--no-preferences` keeps
a capture from reading or writing stored preferences, which is what makes the image
reproducible. One limitation remains, and it only affects captures:

* Forcing an appearance (`NSAppearance`) makes the layer backed labels come out
  blank, so that flag does not exist: captures follow the system appearance, which is
  what the window shows anyway.

## Prebuilt binary (CLI)

Each release ships a standalone macOS binary (arm64) that bundles Python and Rich
— no Python, no uv, no virtualenv required:

```console
gh release download --repo zopyx/usbscope --pattern 'usbscope-*-macos-arm64.tar.gz'
tar xzf usbscope-*-macos-arm64.tar.gz
./usbscope            # or move it to /usr/local/bin
```

`SHA256SUMS` in the release covers both the bare binary and the tarball:

```console
shasum -a 256 -c SHA256SUMS
```

Build it yourself (the script builds, ad-hoc signs, runs the binary once and
packages it into `dist/`):

```console
uv run python scripts/build_binary.py                 # arm64, Python 3.14 + PyInstaller
make binary                                           # same, via make
uv run python scripts/build_binary.py --arch x86_64   # needs an x86_64/universal2 Python
```

Two honest caveats:

* The binary is signed **ad hoc** (`codesign -s -`), not with a Developer ID and
  not notarised. If the download carries the quarantine flag (browsers set it),
  macOS blocks the first start with "cannot be opened because the developer
  cannot be verified". `gh`/`curl` do not set the flag; otherwise remove it with
  `xattr -d com.apple.quarantine ./usbscope`. Notarisation needs a paid Apple
  Developer ID — the build script's `sign()`/`package()` split is where that step
  would go.
* Only the architecture that was built is uploaded (arm64 here). A universal2
  binary requires a universal2 Python to build against.

## Screenshots

`docs/screenshots/` holds SVG + PNG renderings of the four CLI views (plus the
app window shots), generated from a live snapshot of the machine this tool was
written on:

```console
make refresh-screenshots                                        # 140 cols, monokai, 1.5x
SHOT_HOST=macbook make refresh-screenshots                      # mask the host name
uv run python scripts/screenshots.py --png                      # the underlying script
```

Rich exports the recorded console as SVG (colours and box drawing included), so
the gallery can be regenerated on any Mac without a terminal emulator, window
server or screenshot tool; only `rsvg-convert` (librsvg) is needed for the PNG
step. The SVGs are kept next to the PNGs so a future edit can be re-rasterised
without re-collecting. The committed captures use `--host mac`: the header would
otherwise show the real machine name, which does not belong in a public image.
The device inventory and the model/chip line are left as they are — they are
generic hardware facts, not identifiers.

## Development

```console
make sync          # uv sync --extra macapp (dev tools + PyObjC)
make format        # ruff format + ruff check --fix
make lint          # ruff format --check, ruff check, ty check
make test          # pytest
make coverage      # pytest with a coverage report (currently ~90% of src/usbscope)
make check         # lint + test, the CI equivalent
make artifacts     # check + CLI binary + app bundle
```

The same commands, spelled out:

```console
uv run ruff format && uv run ruff check --fix
uv run ty check
uv run pytest
```

`tests/fixtures/` holds real payloads captured on a MacBook Pro (macOS 27.0.1)
plus synthetic payloads for key styles no longer produced by this OS (their
names say so). Parsers are tested against the fixtures; the render tests run
Rich in record mode and assert on the text, never on ANSI codes.

## Swift port

A Swift rewrite of the core plus a CLI twin lives next to the Python package.
The Python tool and its suite stay in place and keep working; the two
implementations are pinned to the *same* fixtures.

| Part | Path |
| --- | --- |
| Package manifest | `Package.swift` (`swift-tools-version: 6.0`, macOS 14+) |
| Core library `UsbScopeCore` | `Sources/UsbScopeCore/` — model, `ioreg`, `system_profiler`, charging, snapshot, JSON serialiser, formatting |
| Presentation library `UsbScopeUI` | `Sources/UsbScopeUI/` — table rows, cell styles, change diffing, detail pairs, TSV/CSV export (no SwiftUI, so it is unit-testable headless) |
| CLI executable `usbscope` | `Sources/usbscope/main.swift` |
| SwiftUI app `usbscope-app` | `Sources/usbscope-app/` — the five views on top of `UsbScopeUI` |
| Test suite | `SwiftTests/` |
| Parity golden | `SwiftTests/Golden/snapshot.json` |

**The acceptance criterion is byte-identical JSON.** `usbscope --json` must
produce the same `schema_version: 1` document from either implementation.

```console
swift build && swift test          # or: make swift
./.build/debug/usbscope --json     # the Swift CLI
uv run usbscope --json             # the Python CLI — the same document
```

`swift test` builds the snapshot from `tests/fixtures` through the Swift
adapters and compares it to `SwiftTests/Golden/snapshot.json`, which
`scripts/swift_golden.py` writes with the Python serialiser (regenerate it with
`make swift-golden` after changing a fixture). A drift in either direction fails
the suite with a leaf-level diff, so the two implementations cannot diverge
unnoticed. Two macOS-specific pitfalls are covered by tests because they broke
parity once and are easy to reintroduce:

* `NSNumber` bridges to `Bool` for the integers `0` and `1` on Darwin, so
  `value is Bool` is not a boolean test — the adapters use `PlistValue.isBool`
  (`CFGetTypeID`), otherwise a pin assignment of `0` or a port number of `1`
  would silently vanish from the JSON.
* `ProcessInfo.processInfo.hostName` returns the Bonjour local name, whereas
  Python's `platform.node()` is `gethostname(3)`; the Swift side calls
  `gethostname` to match.

The Rich terminal rendering is **not** part of the port — the Swift CLI carries
its own small renderer. What the two implementations must agree on is the domain
model, the data adapters and the JSON.

### The SwiftUI app

`usbscope-app` is the SwiftUI twin of the Python/AppKit app: the same five views
(**Ports · Cables · Devices · Thunderbolt · Power**) as a real window, built on
`UsbScopeUI`. The presentation layer is a straight port of
`macapp/viewmodel.py` + `tableops.py` + `changes.py` — the column titles, the
cell text and the sort ranks match the Python app, so the two UIs show the same
numbers in the same order.

```console
swift run usbscope-app              # or: make swift-run-app
make swift-app-check                # headless: row count of every view, then exit
```

| Feature | Behaviour |
| --- | --- |
| Views | Segmented switcher in the toolbar plus `⌘1`–`⌘5` |
| Search | Toolbar field, live filter over every column (all terms must match) |
| Sorting | Click a column header; the sort keys mirror the Python `Cell.sort_value` (a mode rank, a port number) so `USB 1.1` sorts below `USB 3.2 Gen 2` |
| Detail sheet | **Details** button / `⌘D` shows every field of the selected row (port, cable, device or charging metric) |
| Refresh | `⌘R`, plus an auto-refresh toggle and a 2/5/10/30 s interval menu |
| Changes | Rows that appeared, disappeared or changed colour green/red/orange after a refresh; the status line names them |
| Copy / export | `⌘C`/`⇧⌘C` (TSV), `⇧⌘J` (snapshot JSON) to the clipboard; `⌘S`/`⇧⌘S` write JSON/CSV through a save panel |
| Status | Summary line (ports/connected/devices/cables) and a status bar with the read time, cadence, changes and warnings |

**Not ported (yet):** the menu bar extra, the notification banners, the persisted
preferences and the per-row tooltips of the Python app. The window itself needs
no such state to run; `usbscope-app --print-rows` is the headless check the
Python app has as `--snapshot`.

The SwiftUI app also needs an app bundle before macOS will show it as a regular
app with a Dock entry and a proper menu bar; run from the checkout it calls
`NSApplication.setActivationPolicy(.regular)` to bring the window to the front.
Packaging it into a `.app`/DMG is not done yet.

