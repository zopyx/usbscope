# usbscope

Pretty macOS CLI that shows the USB subsystem of your Mac: every receptacle and
its negotiated link mode, the attached devices and what the port controller
knows about the cable (e-marker/SOP, CC authentication, liquid detection).

```console
$ uvx --from . usbscope          # run straight from the checkout
$ usbscope                       # overview  (after `uv tool install .`)
$ usbscope --watch 2             # live refresh
$ usbscope ports -v              # port detail
$ usbscope --json                # machine readable
```

macOS only. No sudo, no private frameworks — `system_profiler` and
`ioreg -p IOPort` are the only data sources.

Documentation: [docs/index.md](docs/index.md)
