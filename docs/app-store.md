# Mac App Store release

Status: **packaging path implemented; submission not performed.** The repository
now has `scripts/build-swift-mas-pkg.sh`, which requires an Apple Distribution
identity, an installer identity, and a provisioning profile, consumes the
entitlements, signs the sandboxed app, validates its entitlements, builds a
signed `.pkg`, and runs `pkgutil --check-signature`. Submission and sandbox
source validation still require Apple-issued credentials.

## What already exists

| Item | State |
| --- | --- |
| Bundle identifier | `com.zopyx.usbscope` (`BUNDLE_ID` in `scripts/build-swift-app.sh`) |
| Version / build number | `CFBundleShortVersionString` = marketing version in `Sources/usbscope/main.swift`; `CFBundleVersion` = positive CI/revision build number |
| Minimum system | `LSMinimumSystemVersion` 14.4 |
| Category | `LSApplicationCategoryType` = `public.app-category.utilities` |
| Icon | `CFBundleIconFile` = `usbscope.icns` from `assets/icon/usbscope.icns` |
| Retina | `NSHighResolutionCapable` |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` (no cryptography to declare) |
| Sandbox entitlements | `assets/entitlements/usbscope.entitlements` — `com.apple.security.app-sandbox`; consumed by `scripts/build-swift-mas-pkg.sh`. |
| Nested binaries | None — the app is a single Mach-O, and macOS 14+ ships the Swift runtime, so there are no embedded frameworks/`.dylib`s to co-sign. The former multi-Mach-O signing risk is gone. |
| In-process data reader | `Sources/UsbScopeCore/IORegistryReader.swift`, the default reader (Plan B below) |

`scripts/build-swift-app.sh` builds the general-purpose bundle. The MAS wrapper
uses it unsigned, embeds the provisioning profile, signs with the supplied
entitlements, validates the result, and builds the installer package.

## What needs the developer account

None of this can be produced from a shell; without it no Mac App Store build exists.

1. **Apple Developer Program** membership (99 €/year).
2. Certificate **Apple Distribution** (portal → Certificates → Apple Distribution, or
   Xcode → Settings → Accounts → Manage Certificates). Signs the app.
3. Certificate **Mac Installer Distribution** / "3rd Party Mac Developer Installer"
   (`-p basic` policy; `security find-identity -v -p basic` shows it). Signs the pkg.
4. **App ID** `com.zopyx.usbscope` with the App Store provisioning profile
   (e.g. `usbscope_mas.provisionprofile`), copied to
   `Contents/embedded.provisionprofile`.
5. **App Store Connect** app record (see the metadata below).

## The build

Run the complete sequence with credentials installed:

```console
scripts/build-swift-mas-pkg.sh \
    --profile usbscope_mas.provisionprofile \
    --app-identity "Apple Distribution: … (TEAMID)" \
    --installer-identity "3rd Party Mac Installer: … (TEAMID)"
```

The script rejects missing profiles, missing signing tools, missing sandbox
entitlements, ad-hoc/non-Apple-Distribution signatures, and the network-client
entitlement before creating the package. The shared bundle validator also
requires `Contents/embedded.provisionprofile` whenever MAS/sandbox validation
is requested.

For a repeatable credentialed package build, dispatch
`.github/workflows/mas-package.yml` with an existing version tag from the
protected `app-store` environment. It imports the Apple Distribution and Mac
Installer Distribution certificates into an ephemeral keychain, materializes
the provisioning profile, runs this package script, and uploads the validated
`.pkg` as a workflow artifact. App Store Connect submission remains a deliberate
human step after reviewing the package and store metadata.

## Upload

```console
# Transporter.app (GUI) — or the command line with an App Store Connect API key:
xcrun altool --upload-app -f dist/usbscope-<version>-mas.pkg -t macos \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

Then in App Store Connect → *My Apps* → usbscope → *Build* pick the uploaded build,
answer the compliance question (already answered by the Info.plist key), and submit.

## App Store Connect: what to fill in

Draft metadata (adjust freely; the *app name* must be unique in the store):

| Field | Suggested value |
| --- | --- |
| Name | `usbscope` |
| Subtitle | `USB ports, cables and link modes` |
| Category | Utilities |
| Promotional text | `See which port runs which device at which USB mode — and what the cable can do.` |
| Description | `usbscope shows what macOS knows about your USB-C ports: which one is connected, which USB mode was negotiated, which transports are active (USB2, USB3, DisplayPort), whether the cable is electronically marked and whether the port controller is clean or has seen liquid. The Devices view lists every attached device with bus, port, negotiated speed and whether macOS restricts it; the Cable view shows the CC authentication, the PD specification revision and the power input; the Thunderbolt view lists the USB4 receptacles. A menu bar extra keeps the state in sight and can announce device changes, and everything the app shows can be exported as JSON or CSV. All data comes from the local system — nothing is sent anywhere.` |
| Keywords | `usb,usb-c,thunderbolt,cable,port,power delivery,hardware,monitor` |
| Support URL | `https://github.com/zopyx/usbscope` |
| Privacy policy | not required while nothing is collected — but a short page is expected; the README section is enough to start |
| App Privacy answers | **Data Not Collected** (no networking, no analytics, no identifiers) |
| Age rating | 4+ (utilities, no objectionable content) |
| Review notes | `usbscope reads the USB/port state that macOS already reports. It reads the IORegistry in-process through IOKit, with a system tool as a fallback. No network access, no data leaves the Mac. The menu bar extra can be switched off with its own menu item. To see data, connect any USB device.` |
| Screenshots | 1280 × 800 and 1440 × 900 (macOS requires 16:10, no alpha); `docs/screenshots/asc-1280x800.png` and `asc-1440x900.png` are prepared, and `make snapshot` regenerates window captures that can be padded to size |

## The open technical question: sandbox vs. the data sources

This is the one thing that decides whether the App Store version works, and it
cannot be answered on this machine.

usbscope learns its data from `system_profiler` and the IORegistry. The
`IOPort` plane is read **in-process** through IOKit by default
(`IORegistryReader`), but the historical `/usr/sbin/ioreg` subprocess is kept as
a fallback and `system_profiler` is still spawned. A sandboxed app may spawn
those children, but the children inherit the sandbox — whether they can still
read the IO registry has to be verified with a real App Store signature.

Measured here: a plain binary with `com.apple.security.app-sandbox` and an ad-hoc
signature **traps at launch** (`Trace/BPT trap: 5`), while the same binary without
the entitlement runs. The sandbox cannot initialise without an Apple-issued
signature plus provisioning profile, so no local sandbox test is possible — the
test needs steps 1–4 above.

**Plan B if the sandbox blocks the subprocesses:** read the IO registry
in-process. This is now **implemented** for the Swift core:
`Sources/UsbScopeCore/IORegistryReader.swift` walks the `IOPort` plane through
IOKit (`IOServiceGetMatchingServices` → `IORegistryEntryCreateCFProperties` →
`IORegistryEntryCreateCFProperty`, children assembled under
`IORegistryEntryChildren`) and returns the exact dictionary shape the parser
consumes, so `IOReg.parsePorts` is untouched.
`IoregSource(runner: IORegistryReader.runner())` is a drop-in replacement for the
subprocess source, and it is the **default** reader — `IORegSourceBackend
.automatic` prefers it and only spawns `/usr/sbin/ioreg` when it fails or reports
no port. `SwiftTests/IORegistryReaderTests` checks it against the live registry
and skips with `XCTSkip` where it cannot be read. On the machine the fixtures were
captured on it parses to identical `Port` values.

What remains open for the App Store: the `system_profiler` data is still a
subprocess in the sandboxed case, and the in-process reader has **not** been
verified inside a real sandboxed bundle — that still needs the App Store signature
from steps 1–4. See `docs/distribution.md`.

## Not done yet

- [ ] Developer Program membership, both certificates, App ID + provisioning profile
- [x] A packaging script: `scripts/build-swift-mas-pkg.sh`
- [x] A protected package workflow: `.github/workflows/mas-package.yml`
- [x] Wire `assets/entitlements/usbscope.entitlements` into the MAS signing step
- [ ] Verify the sandboxed build actually reads data (the question above)
- [ ] If it does not: keep the in-process reader as the whole data path for the
      sandboxed build and reduce/replace the `system_profiler` data
- [ ] App Store Connect app record, metadata, screenshots, privacy answers
- [ ] Upload a build, answer the review questions, submit
