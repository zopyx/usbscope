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
generated with `uv run python scripts/screenshots.py --png`, the standalone
binary with `uv run python scripts/build_binary.py`.
