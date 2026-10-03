# Distribution

The honest state of how `usbscope` is (and is not) distributed. Nothing here
pretends a step is done that has not been done.

**Legend used for every command below**

| Marker | Meaning |
| --- | --- |
| **[ran]** | Executed on the build machine while writing this document; the actual result is quoted. |
| **[flags verified, not run]** | The command exists and its flags were checked with `--help` / `man`, but the command itself was never executed (it needs a Developer ID identity, credentials, or a network round-trip to Apple). |
| **[untested]** | Nothing was executed and no flag was checked; treat as a sketch. |

Tool versions on the machine this was written on: macOS 27.0.1 (build 26A434),
`uname -m` = `arm64`, `xcrun notarytool --version` = `1.1.3 (42)` **[ran]**.

---

## (a) What ships today

Every artifact built from this checkout is:

* **ad-hoc signed** — `codesign -s -`, i.e. `Signature=adhoc` with
  `TeamIdentifier=not set`. It is a valid self-signature, not a certificate.
* **arm64 only** — a single-slice binary, no x86_64 and no universal2.
* **not notarised** — there is no Apple notarisation ticket stapled or online.

The evidence, produced by running the read‑only checks against the current
`dist/`:

```console
$ file dist/usbscope-0.2.0-macos-arm64
dist/usbscope-0.2.0-macos-arm64: Mach-O 64-bit executable arm64                # [ran]

$ codesign -dvvv dist/usbscope-0.2.0-macos-arm64 2>&1 | grep -E 'Signature|Team|Format'
Format=Mach-O thin (arm64)                                                     # [ran]
Signature=adhoc
TeamIdentifier=not set

$ codesign -dvvv dist/usbscope.app 2>&1 | grep -E 'Signature|Team|Format'
Format=app bundle with Mach-O thin (arm64)                                     # [ran]
Signature=adhoc
TeamIdentifier=not set

# The ad-hoc signature is internally consistent …
$ codesign --verify --strict --verbose=2 dist/usbscope.app
dist/usbscope.app: valid on disk                                              # [ran, exit 0]
dist/usbscope.app: satisfies its Designated Requirement

# … but Gatekeeper does not trust it:
$ spctl -a -vvv -t install dist/usbscope.app
dist/usbscope.app: rejected                                                   # [ran, exit 3]
```

### Why Gatekeeper refuses and how a user still opens it

An ad-hoc signature has no Developer ID, so Gatekeeper cannot verify who built
the app and macOS 13+ also refuses to run it. On top of that, a *download*
carries the `com.apple.quarantine` xattr (browsers add it; `gh` and `curl` do
not), which turns the refusal into "cannot be opened because the developer
cannot be verified" or, for a stripped/quarantined copy, "is damaged and can't
be opened".

There are exactly two supported ways past this for a user who trusts the
source:

1. **Right‑click (or Control‑click) → Open → Open.** The first launch of that
   copy is then approved individually and remembered.
2. **Remove the quarantine flag** and open again:

   ```console
   xattr -dr com.apple.quarantine dist/usbscope.app    # or the downloaded .dmg before mounting
   open dist/usbscope.app
   ```

   For the standalone CLI binary the equivalent is
   `xattr -d com.apple.quarantine ./usbscope-0.2.0-macos-arm64`.

Do **not** recommend `spctl --master-disable`; it turns off Gatekeeper
system‑wide and is not an acceptable installation instruction.

The CLI tarball behaves the same: `tar xzf …` then `xattr -d
com.apple.quarantine ./usbscope` if it was fetched through a browser.

---

## (b) The Developer ID path (removes the caveat)

This is the route that makes Gatekeeper say *accepted* without any user
workaround. It needs a **paid Apple Developer Program membership** and a
**Developer ID Application** certificate. None of it exists on this machine:
`security find-identity -v -p codesigning` lists only two `Apple Development`
identities and **no** Developer ID **[ran]**, so every command in this section
is **[flags verified, not run]** unless stated otherwise.

### 1. Create and install the certificate

* Either Xcode → *Settings → Accounts → Manage Certificates… → + → **Developer
  ID Application***, or the Developer portal → *Certificates, Identifiers &
  Profiles* → new **Developer ID Application** certificate.
* It lands in the login keychain under
  `Developer ID Application: NAME (TEAMID)`.

Confirm it is there and note the exact string:

```console
security find-identity -v -p codesigning    # [ran here — Developer ID not present]
```

### 2. Sign with the hardened runtime

The task's exact signing form:

```console
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: NAME (TEAMID)" \
  --identifier com.zopyx.usbscope \
  dist/usbscope.app
```

* `--options runtime` enables the Hardened Runtime, which notarisation requires.
* `--timestamp` embeds a secure timestamp (needed for notarisation; drop it only
  for throwaway local builds).
* `--deep` still works but Apple **deprecated it for signing in macOS 13**
  (`man codesign`: *"DEPRECATED for signing as of macOS 13.0"*). The correct
  order is to sign the nested code first and the bundle last — the app already
  contains `Contents/Frameworks/{AppKit,Foundation,objc,…}` and
  `libpython3.14.dylib` [seen in `codesign --verify --deep`, ran]. If you keep
  `--deep`, understand it can skip or mis-order some nested items.
* For the **CLI binary** use the same flags minus `--deep`:

  ```console
  codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: NAME (TEAMID)" \
    --identifier com.zopyx.usbscope \
    dist/usbscope-0.2.0-macos-arm64
  ```

`--force`, `--deep`, `--options`, `--timestamp`, `--sign`, `--identifier` are
all real `codesign` flags **[flags verified via `man codesign`]**.

### 3. Verify locally

```console
codesign --verify --strict --verbose=2 dist/usbscope.app     # [ran on the ad-hoc build → exit 0]
spctl -a -vvv -t install dist/usbscope.app                   # [ran on the ad-hoc build → "rejected", exit 3]
```

After a real Developer ID signature the second command should print
`accepted` with `source=Developer ID` instead of `rejected`.

### 4. Store notary credentials once (recommended over inline passwords)

```console
xcrun notarytool store-credentials "AC_USBSCOPE" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

`store-credentials` is a real subcommand and `--apple-id/--team-id/--password`
are its real options **[flags verified via `xcrun notarytool store-credentials
--help`]**. Prefer this over passing `--password` inline to `submit`: the
profile name is then all a script (or CI secret) needs to hold, and the
credential never lands in shell history. `--password` here is an **app-specific
password** generated at appleid.apple.com, not the Apple ID password.

### 5. Submit for notarisation

```console
xcrun notarytool submit dist/usbscope-0.2.0-macos-arm64.dmg \
  --keychain-profile "AC_USBSCOPE" --wait
```

`--keychain-profile` and `--wait` are real `submit` options **[flags verified
via `xcrun notarytool submit --help`]**. `--wait` blocks until Apple finishes;
you can also submit without it and poll with
`xcrun notarytool wait <submission-id>` **[subcommand verified]**. On failure,
`xcrun notarytool log <submission-id>` prints the reason **[subcommand
verified]**.

**What to submit.** Notarise the **DMG** (or a `.zip`/`.pkg`) that already
contains the signed `.app`. A bare Mach-O executable cannot be stapled later —
`stapler` supports *"UDIF disk images, code-signed executable bundles, and
signed flat installer packages"* **[ran: `xcrun stapler` usage]** — so the CLI
binary must ship inside a notarised container (DMG/PKG/ZIP) rather than as a
loose file.

### 6. Staple the ticket

```console
xcrun stapler staple dist/usbscope-0.2.0-macos-arm64.dmg
```

`stapler staple [-q] [-v] path` is the real form **[ran: `xcrun stapler`
usage]**. Stapling lets a machine with no network verify the app offline.

### 7. Verify the notarised result

```console
spctl -a -vvv -t install dist/usbscope.app                 # the app inside, after notarisation
xcrun stapler validate dist/usbscope-0.2.0-macos-arm64.dmg # expect: "The validate action worked!"
```

**[flags verified, not run]** — no notarised artifact exists here, so neither
result could be observed. The flags themselves are real: `spctl -a -vvv -t
install` was executed against the **ad-hoc** `.app`/binary above (it returned
`rejected`, exit 3), and `stapler validate[-q][-v] path` is the documented form
in `xcrun stapler`'s usage **[ran]**. Assessing a DMG directly depends on the
policy type; when in doubt assess the `.app` inside the mounted image.

---

## (c) universal2 builds

Today's build scripts default to the **host** architecture:
`scripts/build_binary.py` and `scripts/build_app.py` both set
`--arch`'s default to `platform.machine()` (lines around `default_arch` /
`default=platform.machine()`) and forward it to PyInstaller's
`--target-architecture`. On the arm64 machine this was written on, `make binary`
therefore produces an arm64-only artifact — exactly what `file` shows above.

To *attempt* a universal2 build you would pass the architecture explicitly:

```console
uv run python scripts/build_binary.py --arch universal2          # [untested]
uv run python scripts/build_app.py --arch universal2 --no-dmg    # [untested]
```

**The honest caveat:** `--target-architecture universal2` only works when
*every* slice is available — a universal2 CPython and universal2 builds of the
frozen third-party code (here PyObjC and whatever Rich pulls in). PyInstaller
does not magically merge two single-arch Pythons; if any dependency is a single
thin slice, the build fails or silently stays thin. Every interpreter `uv
python list` reports on this machine is a single-arch
`cpython-…-macos-aarch64-none` build and none is universal2 **[ran]**, so this
has **not** been attempted and the universal2 path is **[untested]**. If a
universal2 binary is required, the reliable route is a universal2 Python plus a
clean build on a machine where
both slices resolve, then verify with `lipo -info dist/usbscope-…` and
`file dist/usbscope-…` (expect `Mach-O universal binary` with `x86_64 arm64`).

Shipping a separate `x86_64` artifact is the simpler alternative, but Intel
macOS support is winding down, so arm64-only is a defensible choice to state
plainly rather than a bug to hide.

---

## (d) Homebrew cask formula sketch

A cask only makes sense once there is a notarised DMG in a GitHub Release. The
formula shape:

```ruby
# Casks/usbscope.rb  (in a tap: zopyx/homebrew-usbscope)
cask "usbscope" do
  version "0.2.0"
  sha256 "<sha256 of usbscope-<version>-macos-arm64.dmg>"

  url "https://github.com/zopyx/usbscope/releases/download/v#{version}/usbscope-#{version}-macos-arm64.dmg"
  name "usbscope"
  desc "Show USB buses, ports, cables and negotiated link modes on a Mac"
  homepage "https://github.com/zopyx/usbscope"

  # LSMinimumSystemVersion is 13.0 in the Info.plist, so Ventura or newer:
  depends_on macos: ">= :ventura"

  # Current artifacts are arm64-only; this encodes that honestly instead of
  # letting Homebrew install a binary that will not launch on Intel.
  depends_on arch: :arm64

  app "usbscope.app"

  caveats do
    "usbscope is ad-hoc signed and not notarised — on first launch, "
    "right-click the app and choose Open."
  end
end
```

Get the hash from the exact DMG that was uploaded:

```console
$ shasum -a 256 dist/usbscope-0.2.0-macos-arm64.dmg
7a5774138611824a383b900a7220c67a9e31c633c6a510ef234c1326eab9beef  dist/usbscope-0.2.0-macos-arm64.dmg
```

**[ran]** — that value is this checkout's DMG; it changes on every rebuild, so
recompute it against the file that was actually uploaded.

**Cask caveats, stated openly:**

* `sha256` is per‑release and the build is **not reproducible** (PyInstaller
  output differs run to run), so the checksum must be pasted from the uploaded
  artifact every time — it cannot be computed ahead of the build.
* Homebrew's `brew audit` prefers notarised apps; with the current ad-hoc
  signature the cask installs but the `caveats` text above is doing the real
  work. Notarisation (section b) removes that awkwardness.
* `depends_on arch: :arm64` is correct while the artifacts are arm64-only. A
  universal cask would drop it.
* `depends_on macos: ">= :ventura"` mirrors `LSMinimumSystemVersion 13.0`
  written into the Info.plist by `scripts/build_app.py`.
* No tap repository exists yet; `Casks/usbscope.rb` above is a **sketch**
  **[untested]**.

---

## (f) The Swift app bundle — and what it does *not* do

`scripts/build_swift_app.py` builds the SwiftUI app into `dist/usbscope-swift.app`
(separate from the Python `dist/usbscope.app` that `make app-bundle` produces).
[ran] on this machine (macOS 27.0.1, arm64):

```console
$ uv run python scripts/build_swift_app.py
$ swift build -c release --product usbscope-app
…
$ codesign --force --deep --sign - --identifier com.zopyx.usbscope dist/usbscope-swift.app
$ codesign --verify --verbose=2 dist/usbscope-swift.app
dist/usbscope-swift.app: valid on disk
dist/usbscope-swift.app: satisfies its Designated Requirement
$ dist/usbscope-swift.app/Contents/MacOS/usbscope-app --version
usbscope-app 0.4.0
ad-hoc signed (codesign --verify OK)
  --version → usbscope-app 0.4.0
  --print-rows → 7 lines (live data path OK)
  Info.plist: com.zopyx.usbscope 0.4.0 (min macOS 14.0)
dist/usbscope-swift.app  (1.4 MiB, usbscope)
```

What the script does:

* `swift build -c release --product usbscope-app` (or `--debug`), then
  `swift build -c release --show-bin-path` to locate the executable.
* assembles `Contents/MacOS/usbscope-app`, `Contents/Info.plist` and, when
  `assets/icon/usbscope.icns` exists, `Contents/Resources/usbscope.icns`.
* writes `CFBundleIdentifier com.zopyx.usbscope`, the `pyproject.toml` version as
  `CFBundleShortVersionString`/`CFBundleVersion`, `LSMinimumSystemVersion 14.0`,
  `NSHighResolutionCapable`, `CFBundleIconFile`, `LSApplicationCategoryType` and
  `ITSAppUsesNonExemptEncryption = false`.
* ad-hoc signs (`codesign --force --deep --sign -`) and **verifies** the signature.
* runs the bundled binary (`--version`, plus `--print-rows` when a window server is
  available) and refuses to finish if it does not start.
* prints every command it runs; `--no-sign`, `--no-verify`, `--no-icon`, `--debug`
  and `--name` change what it does. A missing icon or a failed code signing step
  stops the build with a clear message instead of leaving a half-built bundle.

What it does **not** do — the honest gaps, all of which need an Apple Developer
account that does not exist on this machine:

* **No Developer ID signature.** `--sign -` is ad hoc (`Signature=adhoc`,
  `TeamIdentifier=not set`); `spctl -a -vvv -t install dist/usbscope-swift.app`
  still reports `rejected` exactly as in section (a).
* **No hardened runtime** (`--options runtime`) and **no secure timestamp**
  (`--timestamp`) — notarisation requires both.
* **No notarisation and no stapling.** There is no `notarytool submit` step and no
  `stapler staple`, and — as in section (b) — an `.app` must travel inside a
  `.zip`/`.dmg`/`.pkg` to be stapled (`ditto -c -k --keepParent` or a DMG).
* **No DMG, no checksums.** The script stops at the `.app`; there is no
  `SHA256SUMS-swift` next to it.
* **No universal2 / x86_64 slice.** The bundle is the host architecture only
  (`arm64` here). `swift build --arch x86_64 --arch arm64` plus `lipo` would be the
  route; untested.
* **No entitlements, no sandbox, no App Store packaging.** The Swift app carries no
  entitlements and `make mas-pkg` (`scripts/make_mas_pkg.py`) targets the *Python*
  app, not this bundle.
* **Not reproducible.** The Mach-O embeds build paths and a UUID, so two builds
  differ byte for byte; there is no `--build-timestamp`/deterministic-inputs setup.

### What hardening the Swift app still needs

The steps are the same six as section (b), applied to a much simpler bundle — the
Swift app is a single Mach-O with **no embedded frameworks** (macOS 14+ ships the
Swift runtime), so there is nothing nested to sign and the 1.4 MiB size is the whole
bundle:

```console
# [flags verified, not run] — no Developer ID identity exists on this machine
codesign --force --options runtime --timestamp --sign "Developer ID Application: NAME (TEAMID)" \
    --identifier com.zopyx.usbscope dist/usbscope-swift.app
codesign --verify --strict --verbose=2 dist/usbscope-swift.app
spctl -a -vvv -t install dist/usbscope-swift.app            # expect: accepted, source=Developer ID
ditto -c -k --keepParent dist/usbscope-swift.app dist/usbscope-swift.zip
xcrun notarytool submit dist/usbscope-swift.zip --keychain-profile "AC_USBSCOPE" --wait
xcrun stapler staple dist/usbscope-swift.app                # or staple the zip/dmg container
```

Because there are no nested binaries, a single `codesign` of the bundle is
sufficient — `--deep` is unnecessary here even though the build script still passes
it for symmetry with the Python path.

---

## (g) Not done yet — explicit checklist

- [ ] Developer ID Application certificate issued and installed (only Apple
      Development certs exist on this machine **[ran]**).
- [ ] Real Developer ID signing in the build scripts — `scripts/build_app.py`
      `sign()` and `scripts/build_binary.py` `sign()` both do `codesign -s -`
      (ad-hoc) and the signing authority is hard-coded to `-`.
- [ ] Hardened Runtime (`--options runtime`) on both the app and the CLI binary.
- [ ] Notarisation and stapling wired into a release flow (none exists).
- [ ] A release pipeline (tag → build → sign → notarise → staple → upload);
      artifacts are currently produced by hand with `make artifacts`.
- [ ] CI that signs/notarises — the new `.github/workflows/ci.yml` only runs the
      gates and uploads *unsigned* ad-hoc build artifacts, with **no** signing
      secrets. Distribution signing does not happen in CI at all.
- [ ] universal2 or x86_64 builds (current output is arm64-only, verified with
      `file`).
- [ ] Notarised packaging for the standalone CLI binary — a bare Mach-O cannot
      be stapled, so it needs a DMG/PKG/ZIP wrapper.
- [ ] Homebrew tap and cask published.
- [ ] `SHA256SUMS`/`SHA256SUMS-app` consumed by any automated downloader; today
      they are generated but nothing verifies them downstream.
- [ ] The **Swift** app bundle (`dist/usbscope-swift.app`) Developer-ID signed with
      `--options runtime --timestamp`, notarised and stapled (section f); it has no
      DMG, no checksums and no universal2 slice either.
- [ ] The in-process IOKit reader (`Sources/UsbScopeCore/IORegistryReader.swift`)
      wired into the *app* build path (it is implemented and tested, but the Swift
      `SnapshotBuilder` still spawns `ioreg` today) and verified inside a real
      sandboxed bundle.

Until the boxes above are ticked, every artifact is **ad-hoc signed, arm64-only
and not notarised**, and `docs/index.md` / this file should say exactly that.
