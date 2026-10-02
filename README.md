# usbscope

Pretty macOS CLI that shows the USB subsystem of your Mac: every receptacle and
its negotiated link mode, the attached devices and what the port controller
knows about the cable (e-marker/SOP, CC authentication, liquid detection).

![usbscope overview](docs/screenshots/overview.png)

## Ports & cables

Every receptacle with its state, the negotiated USB mode, the active/idle
transports (CC, USB2, USB3, DisplayPort), the cable class, and notes: attached
devices, DisplayPort alt mode, power delivery, liquid detection, macOS
restrictions.

![usbscope ports](docs/screenshots/ports.png)

## Cables & port controller

![usbscope cables](docs/screenshots/cables.png)

## Devices

![usbscope devices](docs/screenshots/devices.png)

## A native macOS app

The same data in a real Cocoa window (`usbscope-app`): unified toolbar with a view
switcher and a live search field, sortable column headers, `⌘1`–`⌘4`, `⌘C`/`⇧⌘C`
for TSV, double click for a detail popover, JSON/CSV export, a refresh that keeps
your selection and scroll position, green/red row marks when a device appears or
disappears, a menu bar extra (`2/6` with connect/disconnect banners) and everything
remembered across launches.

![usbscope app](docs/screenshots/app-ports.png)

```console
$ uv run --extra macapp usbscope-app      # run from the checkout
$ make icon                               # regenerate the app icon
$ make app-bundle                         # usbscope.app + styled DMG into dist/
$ open ~/src/usbscope/dist/usbscope.app   # or drag it out of the DMG into /Applications
```

Connect/disconnect banners only appear from the installed bundle — macOS aborts a
notification request from a plain interpreter run (see
[docs/index.md](docs/index.md)).

## Build & verify

```console
$ make                # list the tasks (self documenting)
$ make doctor         # uv, PyObjC, librsvg, codesign, hdiutil available?
$ make check          # gates: ruff format --check, ruff check, ty, pytest
$ make binary         # standalone CLI binary        → dist/
$ make app-bundle     # usbscope.app + styled DMG    → dist/
$ make artifacts      # gates + both builds (release build)
$ make checksums      # verify the SHA-256 files in dist/
```

CI (`.github/workflows/ci.yml`) runs the same four gates on every push and pull
request on an arm64 macOS runner, plus the two builds on `main`. Signing,
notarisation and the Homebrew cask — and what is still missing there — are in
[docs/distribution.md](docs/distribution.md).

## Usage

```console
$ uvx --from . usbscope          # run straight from the checkout
$ usbscope                       # overview  (after `uv tool install .`)
$ usbscope --watch 2             # live refresh (alternate screen, no flicker)
$ usbscope ports -v              # port detail
$ usbscope cables                # e-marker, CC authentication, liquid detection
$ usbscope --json                # machine readable
```

Or take the prebuilt binary from the
[latest release](https://github.com/zopyx/usbscope/releases) (macOS arm64, no
Python needed):

```console
gh release download --repo zopyx/usbscope --pattern 'usbscope-*-macos-arm64.tar.gz'
tar xzf usbscope-*-macos-arm64.tar.gz && ./usbscope
```

macOS only. No sudo, no private frameworks, no entitlements — `system_profiler`
and `ioreg -p IOPort` are the only data sources.

Documentation: [docs/index.md](docs/index.md). The screenshots above are
generated with `uv run python scripts/screenshots.py --png --host mac`, the
standalone binary with `uv run python scripts/build_binary.py`.
