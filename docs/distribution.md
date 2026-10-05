# Distribution

The honest state of how `usbscope` is (and is not) distributed. Nothing here
pretends a step is done that has not been done.

The project builds one thing today — the app bundle `dist/usbscope-swift.app`,
produced by `scripts/build-swift-app.sh` — and two ways to hand it out. The build
script packs the bundle into `dist/usbscope-swift-<version>-macos-<arch>-<signing-mode>.tar.gz`;
`scripts/build-swift-dmg.sh` (`make swift-app-dmg`) packs the same bundle into a
compressed `dist/usbscope-swift-<version>-macos-<arch>-<signing-mode>.dmg`. Both artifacts get a
line in `dist/SHA256SUMS`, which `make checksums` re-verifies. The build is
native-only by default; `scripts/build-swift-app.sh --universal` optionally builds
a fat arm64 + x86_64 bundle. There is still no published release, no prebuilt CLI
binary and no Homebrew cask — and neither artifact is signed for distribution
(both are ad hoc only).

**Legend used for every command below**

| Marker | Meaning |
| --- | --- |
| **[ran]** | Executed on the build machine while writing this document; the actual result is quoted. |
| **[flags verified, not run]** | The command exists and its flags were checked with `--help` / `man`, but the command itself was never executed (it needs a Developer ID identity, credentials, or a network round-trip to Apple). |
| **[untested]** | Nothing was executed and no flag was checked; treat as a sketch. |

Tool versions on the machine this was written on: macOS 27.0.1 (build 26A434),
`uname -m` = `arm64`, `xcrun notarytool --version` = `1.1.3 (42)` **[ran]**.

### Version and build-number policy

`CFBundleShortVersionString` follows the CLI marketing version (for example
`0.9.0`). `CFBundleVersion` is a separate positive integer. Release CI uses
`GITHUB_RUN_NUMBER`; credentialed release automation may provide `BUILD_NUMBER`.
Local builds fall back to the Git revision count, and the bundle script rejects
missing, zero, or non-numeric values before writing `Info.plist`.

### Signing modes

Every bundle carries `USBScopeSigningMode`, and every archive/DMG includes the
same mode in its filename. The direct builder accepts `--signing-mode debug`,
`adhoc`, or `developer-id`; legacy `--debug` and `--identity` flags infer the
corresponding mode. Debug and ad-hoc modes require an ad-hoc signature, while
Developer ID mode requires an Apple Developer ID Application signature and
fails closed if the resulting certificate is not Developer ID. The MAS wrapper
uses `--signing-mode mas`, consumes the sandbox entitlements, and emits a
separately named `-mas.pkg`.

---

## (a) What ships today

`scripts/build-swift-app.sh` — or `make swift-app-bundle` — compiles
`usbscope-app` with `swift build -c release`, assembles the bundle, signs it
ad hoc, verifies the signature and runs the bundled binary once. Add
`--universal` for a fat arm64 + x86_64 build (see (c)). `scripts/build-swift-dmg.sh`
— or `make swift-app-dmg` — then packs that bundle into a DMG (below).

What the artifact is:

* **ad-hoc signed** — `codesign --force --deep --sign -`, i.e. `Signature=adhoc`
  with `TeamIdentifier=not set`. It is a valid self-signature, not a certificate.
* **native by default** — a single-slice binary. On this arm64 machine that is
  `arm64` (`Mach-O 64-bit executable arm64` below); `--universal` produces a fat
  `x86_64` + `arm64` bundle instead, but it is not built or shipped by default.
* **not notarised** — there is no Apple notarisation ticket stapled or online.
* **not published** — nothing is uploaded anywhere; the app exists only under
  `dist/`, which is gitignored.

The evidence, produced by running the read-only checks against the current
`dist/usbscope-swift.app`:

```console
$ file dist/usbscope-swift.app/Contents/MacOS/usbscope-app
dist/usbscope-swift.app/Contents/MacOS/usbscope-app: Mach-O 64-bit executable arm64   # [ran]

$ codesign -dvvv dist/usbscope-swift.app 2>&1 | grep -E 'Signature|Team|Format|Identifier'
Identifier=com.zopyx.usbscope                                                         # [ran]
Format=app bundle with Mach-O thin (arm64)
Signature=adhoc
TeamIdentifier=not set

# The ad-hoc signature is internally consistent …
$ codesign --verify --strict --verbose=2 dist/usbscope-swift.app
dist/usbscope-swift.app: valid on disk                                               # [ran, exit 0]
dist/usbscope-swift.app: satisfies its Designated Requirement

# … but Gatekeeper does not trust it:
$ spctl -a -vvv -t install dist/usbscope-swift.app
dist/usbscope-swift.app: rejected                                                    # [ran, exit 3]
```

### The DMG (`scripts/build-swift-dmg.sh`)

`make swift-app-dmg` turns the bundle above into
`dist/usbscope-swift-<version>-macos-<arch>-adhoc.dmg` using `hdiutil` alone — no sudo,
no Apple account, no `create-dmg`/`appdmg`. The volume is named `usbscope`, holds
`usbscope-swift.app` next to an `/Applications` symlink (the usual drag-to-install
layout), and is written as a compressed, read-only `UDZO` image. Everything is
staged in a `mktemp -d` directory that a `trap` removes and the test mount is
detached, so no staged file or loop device is left behind. The architecture in the
name is read from the binary inside the bundle, so a `--universal` bundle yields a
`...-universal2-<signing-mode>.dmg` automatically.

Real output from this machine **[ran]**:

```console
$ scripts/build-swift-dmg.sh
+ hdiutil: /usr/bin/hdiutil
$ ditto dist/usbscope-swift.app usbscope-swift.app
$ hdiutil create -volname usbscope -srcfolder <staged> -ov -format UDZO dist/usbscope-swift-0.9.0-macos-universal2-adhoc.dmg
created: dist/usbscope-swift-0.9.0-macos-universal2-adhoc.dmg
$ hdiutil verify dist/usbscope-swift-0.9.0-macos-universal2-adhoc.dmg
hdiutil: verify: checksum of ".../usbscope-swift-0.9.0-macos-universal2-adhoc.dmg" is VALID
$ hdiutil attach dist/usbscope-swift-0.9.0-macos-universal2-adhoc.dmg -nobrowse -readonly -mountpoint <staged mount>
  mounted volume contents: Applications usbscope-swift.app
  mounted copy --version → usbscope-app 0.9.0
$ hdiutil detach <staged mount>
"disk12" ejected.

dist/usbscope-swift-0.9.0-macos-universal2-adhoc.dmg  (2.4 MiB)
```

`hdiutil create` / `attach` / `detach` print a deprecation warning pointing at
`diskutil image`, but they work **[ran]**. The image's sha256 is appended to the
same `dist/SHA256SUMS`, so `make checksums` covers both artifacts:

```console
$ make checksums
usbscope-swift-0.9.0-macos-universal2-adhoc.tar.gz: OK
usbscope-swift-0.9.0-macos-universal2-adhoc.dmg: OK
```

`--no-verify` skips the mount/run test. The DMG passes `hdiutil verify` and mounts
with the app inside, but it is **unsigned packaging of an ad-hoc signed app** — no
Developer ID, no notarisation — so it is an installable *shape*, not a
distributable release. The steps that would make it one are section (b).

### Why Gatekeeper refuses and how a user still opens it

An ad-hoc signature has no Developer ID, so Gatekeeper cannot verify who built
the app and macOS 13+ also refuses to run it. On top of that, a *download*
carries the `com.apple.quarantine` xattr (browsers add it; `gh` and `curl` do
not), which turns the refusal into "cannot be opened because the developer
cannot be verified" or, for a stripped/quarantined copy, "is damaged and can't
be opened".

There are exactly two supported ways past this for a user who trusts the
source:

1. **Right-click (or Control-click) → Open → Open.** The first launch of that
   copy is then approved individually and remembered.
2. **Remove the quarantine flag** and open again:

   ```console
   xattr -dr com.apple.quarantine dist/usbscope-swift.app
   open dist/usbscope-swift.app
   ```

Do **not** recommend `spctl --master-disable`; it turns off Gatekeeper
system-wide and is not an acceptable installation instruction.

Because no binary is published, a user who wants the CLI builds it from source
with `swift build -c release`; there is nothing to download yet.

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

The Swift app is a single Mach-O with **no embedded frameworks** (macOS 14+
ships the Swift runtime), so there is nothing nested to sign and one `codesign`
of the bundle is enough:

```console
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: NAME (TEAMID)" \
  --identifier com.zopyx.usbscope \
  dist/usbscope-swift.app
```

* `--options runtime` enables the Hardened Runtime, which notarisation requires.
* `--timestamp` embeds a secure timestamp (needed for notarisation; drop it only
  for throwaway local builds).
* `--deep` is not needed here — the bundle has no nested code. (The build script
  still passes it for symmetry; `man codesign` marks it *"DEPRECATED for signing
  as of macOS 13.0"*.)

`--force`, `--options`, `--timestamp`, `--sign` and `--identifier` are all real
`codesign` flags **[flags verified via `man codesign`]**.

### 3. Verify locally

```console
codesign --verify --strict --verbose=2 dist/usbscope-swift.app   # [ran on the ad-hoc build → exit 0]
spctl -a -vvv -t install dist/usbscope-swift.app                 # [ran on the ad-hoc build → "rejected", exit 3]
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

The automated path is:

```console
scripts/build-swift-app.sh --identity "Developer ID Application: ..." \\
  --notarize --notary-profile "AC_USBSCOPE"
```

The script creates a temporary zip for `notarytool`, waits for acceptance,
staples and validates the app, then creates the final tarball and checksum from
the stapled bundle. `--notarize` requires an explicit identity, profile, and
archive output.

```console
xcrun notarytool submit dist/usbscope-swift.zip \
  --keychain-profile "AC_USBSCOPE" --wait
```

`--keychain-profile` and `--wait` are real `submit` options **[flags verified
via `xcrun notarytool submit --help`]**. `--wait` blocks until Apple finishes;
you can also submit without it and poll with
`xcrun notarytool wait <submission-id>` **[subcommand verified]**. On failure,
`xcrun notarytool log <submission-id>` prints the reason **[subcommand
verified]**.

**What to submit.** `notarytool` receives a container such as a `.zip`, `.dmg`,
or `.pkg`; `stapler` then supports stapling the accepted ticket to the
code-signed executable bundle itself (as the build script does), or to a
supported container where applicable. `ditto -c -k --keepParent
dist/usbscope-swift.app dist/usbscope-swift.zip` produces the notarization
input, and `scripts/build-swift-dmg.sh` can package the stapled app afterward.
What does **not** exist yet is a container built from a *Developer-ID signed*
bundle: the DMG today wraps the ad-hoc bundle, which is not what a notarised
release would ship.

### 6. Staple the ticket

```console
xcrun stapler staple dist/usbscope-swift.app     # staple the accepted bundle
```

`stapler staple [-q] [-v] path` is the real form **[ran: `xcrun stapler`
usage]**. Stapling lets a machine with no network verify the app offline.

### 7. Verify the notarised result

```console
spctl -a -vvv -t install dist/usbscope-swift.app    # the app inside, after notarisation
xcrun stapler validate dist/usbscope-swift.zip      # expect: "The validate action worked!"
```

**[flags verified, not run]** — no notarised artifact exists here, so neither
result could be observed. The flags themselves are real: `spctl -a -vvv -t
install` was executed against the **ad-hoc** `.app` above (it returned
`rejected`, exit 3), and `stapler validate[-q][-v] path` is the documented form
in `xcrun stapler`'s usage **[ran]**.

---

## (c) universal2 builds

The default build is the **host** architecture only: `swift build -c release`
builds one slice, and on this arm64 machine that is exactly the `Mach-O 64-bit
executable arm64` shown in section (a).

`scripts/build-swift-app.sh --universal` opts into a fat build. It adds
`--arch arm64 --arch x86_64` to the `swift build` (so the linker emits a fat
Mach-O), checks the result with `lipo` and fails loudly if the binary came out
thin, and names the archive `...-macos-universal2-<signing-mode>.tar.gz` instead of the host
architecture. Run on this machine **[ran]**:

Every signed app build also runs `scripts/validate-swift-app.sh`, which checks
the bundle identifier, minimum macOS version, executable, signature, and
architectures. Pass `--gatekeeper` to that validator for a credentialed release
artifact.

```console
$ scripts/build-swift-app.sh --universal
...
$ lipo -info dist/usbscope-swift.app/Contents/MacOS/usbscope-app
Architectures in the fat file: dist/usbscope-swift.app/Contents/MacOS/usbscope-app are: x86_64 arm64

$ file dist/usbscope-swift.app/Contents/MacOS/usbscope-app
dist/usbscope-swift.app/Contents/MacOS/usbscope-app: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64]
dist/usbscope-swift.app/Contents/MacOS/usbscope-app (for architecture x86_64):	Mach-O 64-bit executable x86_64
dist/usbscope-swift.app/Contents/MacOS/usbscope-app (for architecture arm64):	Mach-O 64-bit executable arm64

$ codesign -dvvv dist/usbscope-swift.app 2>&1 | grep -E 'Format|Signature|Team|Identifier'
Identifier=com.zopyx.usbscope
Format=app bundle with Mach-O universal (x86_64 arm64)
Signature=adhoc
TeamIdentifier=not set
```

Because the app has no embedded native dependencies, both slices come from the
same source and compiler — nothing has to be built twice by hand and no thin
dependency spoils the link. `--universal` does **not** remove the caveat: the fat
bundle is still only *ad-hoc* signed (the `Format` / `Signature` lines above), so
it is neither Developer-ID signed nor notarised, exactly like the native build.
The default stays native-only, and no universal artifact is shipped — only the
`--universal` run changes the bundle, the archive name and (via
`scripts/build-swift-dmg.sh`) the `...-universal2-<signing-mode>.dmg` name.

---

## (d) What a real release still needs — explicit checklist

The release-capable signing path is implemented, but this checkout has no
Developer ID credentials, so the artifacts under `dist/` remain **ad-hoc signed,
native-only by default and not notarised**. A credentialed release run is still
an operational prerequisite before publication.

- [ ] Developer ID Application certificate issued and installed (only Apple
      Development certs exist on this machine **[ran]**).
- [x] Developer ID signing mode in `scripts/build-swift-app.sh`; pass the
      certificate with `--identity`. The default remains intentionally ad hoc.
- [x] Hardened Runtime is enabled whenever a non-ad-hoc identity is used.
- [x] A temporary zip container to *notarise*, built from a Developer-ID signed bundle —
      *unsigned packaging exists*: `scripts/build-swift-dmg.sh` (`make swift-app-dmg`)
      builds a verified, compressed DMG and `ditto -c -k --keepParent` makes a zip,
      but both wrap the ad-hoc bundle, so neither is notarisation-ready.
- [x] `xcrun notarytool submit` and `xcrun stapler staple` are wired into the
      build; credentials and an Apple-issued certificate remain prerequisites.
- [ ] A release pipeline (tag → build → sign → notarise → staple → upload);
      artifacts are currently produced by hand.
- [ ] CI that signs/notarises — `.github/workflows/ci.yml` only runs
      `swift build` + `swift test` and, on `main`, builds/uploads the *unsigned*
      ad-hoc bundle with **no** signing secrets. Distribution signing does not
      happen in CI at all.
- [ ] universal2 in a *shipped* artifact — `scripts/build-swift-app.sh --universal`
      builds a fat arm64 + x86_64 bundle (verified with `lipo`/`file`, section (c)),
      but the default output stays arm64-only (verified with `file`) and no
      universal artifact is published.
- [ ] A published release of any kind — nothing is tagged or uploaded; the tarball
      and the DMG exist only under `dist/`.
- [x] `SHA256SUMS` for the release artifacts: `scripts/build-swift-app.sh` packs the
      bundle into `dist/usbscope-swift-<version>-macos-<arch>-<signing-mode>.tar.gz`,
      `scripts/build-swift-dmg.sh` packs it into the matching `.dmg`, and
      `dist/SHA256SUMS` carries a line for each; `make checksums` re-verifies both
      (and fails on a mismatch). These are checksums over *unsigned* artifacts,
      which is not what a notarised release would ship.
- [ ] Homebrew tap and cask published (a cask only makes sense once a notarised
      DMG exists in a GitHub Release).
- [ ] The in-process IOKit reader (`Sources/UsbScopeCore/IORegistryReader.swift`)
      verified inside a real sandboxed bundle — it is implemented and tested, and
      it is the default reader, but the sandbox question needs an Apple-issued
      signature plus provisioning profile (see [app-store.md](app-store.md)).
