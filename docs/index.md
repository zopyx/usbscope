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
| `cables` | cable class (passive / e-marked / active / optical), CC authentication + hash status, SOP spec revision, LDCM liquid status, controller firmware |
| `thunderbolt` | Thunderbolt/USB4 receptacles: state, link speed, host adapter |

`-v/--verbose` adds raw detail (location IDs, plug orientation, TRM state,
per-transport rate/signaling/lanes, CC hash status, SOP revision, sources).

## Columns of the port table

| Column | Meaning |
| --- | --- |
| Port | receptacle from the port controller, e.g. `USB-C@3` (`@N` is the hardware port number) |
| Type | `USB-C`, `MagSafe 3`, `HDMI`, `SD Card` |
| State | `ConnectionActive` reported by the port controller |
| Negotiated mode | link mode of the active USB transport, derived from the negotiated rate |
| Transports | `CC` (configuration channel), `USB2`, `USB3`, `DP` (DisplayPort alt mode), `SD`; `●` active, `○` idle |
| Cable | cable class; e-marked means the controller received a SOP e-marker response |
| Notes | attached device(s), DisplayPort alt mode, liquid detection, accessory authorization, macOS restriction (TRM) |

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
| `ioreg -a -l -w0 -p IOPort` | port controller view: ports, transport states, cable/CC/SOP data, LDCM, TRM |

Both sources are optional at runtime: a failing source only adds a warning that
is rendered in a yellow *notes* panel (or in `warnings[]` of the JSON), it never
aborts the run.

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
* **`restricted by macOS`** mirrors the port controller's `TRM_TransportRestricted`
  flag (the "allow accessory to connect" prompt used from macOS 13 on).
* Thunderbolt link speed is the *cable capability* reported per receptacle, not
  the negotiated lane rate.

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
| `make run` / `make watch` / `make run-app` | CLI overview, CLI with live refresh, native app |
| `make snapshot` | app window → `docs/screenshots/app-<view>.png` (offscreen, no permissions needed) |
| `make refresh-screenshots` | CLI screenshots (SVG + PNG, host name masked) |
| `make screenshots` | both of the above |
| `make binary` | standalone CLI binary → `dist/` |
| `make app-bundle` (alias `make app`) | `usbscope.app` + DMG → `dist/` |
| `make artifacts` | gates + CLI binary + app: the full release build |
| `make checksums` | verifies `dist/SHA256SUMS` and `dist/SHA256SUMS-app` |
| `make install` | `uv tool install '.[macapp]'` (CLI + `usbscope-app` on the PATH) |
| `make clean` / `make distclean` | build output / plus the virtualenv |

Variables: `SHOT_HOST=<name> make refresh-screenshots` sets the host name shown in
the captures (default `mac`). On macOS two details matter: `make` is the old GNU
make 3.81 (no modern functions in the file), and the shell already exports a `HOST`
variable — which is why the screenshot variable is called `SHOT_HOST`.

## The macOS app

The same data as a native Cocoa app (`usbscope-app`) — a real `NSWindow` with a
segmented view switcher, a view based `NSTableView`, `⌘R`, an auto-refresh timer
and an Info.plist bundle you can drop into `/Applications`:

![usbscope app](docs/screenshots/app-ports.png)

```console
$ usbscope-app                    # from a checkout (needs the macapp extra)
$ open dist/usbscope.app          # or the built bundle / the release DMG
```

Views: **Ports** (state, negotiated mode, transports, cable, notes), **Cables**
(CC authentication, hash, PD spec revision, power in, liquid detection, controller
firmware), **Devices** (flat table with bus, port, transport, serial, macOS
restriction and per-row tooltips) and **Thunderbolt**. Auto-refresh runs every
1/2/5/10 s and can be switched off; the status line shows the read counter, the
cadence and the first warning of a failing source.

```console
$ uv run --extra macapp usbscope-app          # run from the checkout
$ make run-app                                # same, via make
$ make app-bundle                             # build + verify + DMG into dist/
```

### Building the bundle

`make app-bundle` (or `uv run python scripts/build_app.py`) runs four steps and
fails loudly at each one instead of leaving a broken artifact:

1. **PyInstaller** (`--windowed --target-architecture arm64`) collects Python, Rich
   and PyObjC plus a generated entry point into `dist/usbscope.app`. Only `uv` is
   required — PyInstaller and PyObjC are fetched on demand; `codesign` and
   `hdiutil` ship with macOS.
2. **Info.plist** is rewritten with `CFBundleIdentifier com.zopyx.usbscope`, the
   package version, `LSMinimumSystemVersion 13.0` and `NSHighResolutionCapable`, so
   Finder shows a proper name and macOS knows the minimum system.
3. **Signing**: `codesign --deep --force --sign - --identifier com.zopyx.usbscope`
   (ad hoc), followed by `codesign --verify`.
4. **Self test**: the *bundled* app is executed —
   `dist/usbscope.app/Contents/MacOS/usbscope --snapshot … --view ports` — and the
   resulting PNG is checked. A windowed app still takes argv, which is how the build
   proves the artifact works before packaging. Then `hdiutil create … UDZO` writes
   the DMG and `SHA256SUMS-app`.

| Artifact | Content |
| --- | --- |
| `dist/usbscope.app` | the bundle (drag into `/Applications`) |
| `dist/usbscope-0.2.0-macos-arm64.dmg` | compressed disk image (~11 MiB) |
| `dist/SHA256SUMS-app` | SHA-256 of the DMG |
| `dist/usbscope-<version>-macos-arm64[.tar.gz]` | standalone CLI binary (12.7 MiB) |
| `dist/SHA256SUMS` | SHA-256 of both CLI artifacts |

Install and check the built artifacts:

```console
make checksums                                            # both checksum files
open dist/usbscope-0.2.0-macos-arm64.dmg                  # then drag the app over
/Volumes/usbscope/usbscope.app/Contents/MacOS/usbscope --version
```

`usbscope-app --snapshot out.png [--view cables]` renders the window offscreen
(`make snapshot` regenerates `docs/screenshots/app-*.png`). Two known limitations of
that capture path — the interactive app is not affected:

* AppKit's control cells (segment titles, popup items, button bezels) do not
  serialise into an offscreen bitmap. In `--snapshot` mode the toolbar is therefore
  drawn as plain text labels at the same place; the real window uses the native
  controls.
* Forcing an appearance (`NSAppearance`) for a capture makes the layer backed labels
  come out blank, so that flag does not exist: captures follow the system
  appearance, which is what the window shows anyway.

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

`docs/screenshots/` holds SVG + PNG renderings of the four views, generated from a
live snapshot of the machine this tool was written on:

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
