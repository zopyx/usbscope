# Distribution

The honest state of how `usbscope` is (and is not) distributed. Nothing here
pretends a step is done that has not been done.

The project builds **one** artifact today: `dist/usbscope-swift.app`, produced by
`scripts/build-swift-app.sh`. There is no published release, no DMG, no prebuilt
CLI binary and no Homebrew cask.

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

`scripts/build-swift-app.sh` — or `make swift-app-bundle` — compiles
`usbscope-app` with `swift build -c release`, assembles the bundle, signs it
ad hoc, verifies the signature and runs the bundled binary once. It is the only
build path in the repository.

What the artifact is:

* **ad-hoc signed** — `codesign --force --deep --sign -`, i.e. `Signature=adhoc`
  with `TeamIdentifier=not set`. It is a valid self-signature, not a certificate.
* **arm64 only** — a single-slice binary, no x86_64 and no universal2.
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

**What to submit.** An `.app` cannot be stapled directly — `stapler` supports
*"UDIF disk images, code-signed executable bundles, and signed flat installer
packages"* **[ran: `xcrun stapler` usage]** — so the bundle must travel inside a
`.zip`/`.dmg`/`.pkg`. `ditto -c -k --keepParent dist/usbscope-swift.app
dist/usbscope-swift.zip` produces such a container. **No packaging step exists
yet** (see the checklist); the build script stops at the `.app`.

### 6. Staple the ticket

```console
xcrun stapler staple dist/usbscope-swift.zip     # or the .dmg/.pkg container
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

Today's build is the **host** architecture only: `swift build -c release` builds
one slice, and on this arm64 machine that is exactly the `Mach-O 64-bit
executable arm64` shown in section (a).

A universal2 app would need a build with both slices plus `lipo`. The Swift
route — untested here:

```console
swift build -c release --product usbscope-app --arch arm64 --arch x86_64   # [untested]
lipo -info .build/release/usbscope-app                                    # expect: x86_64 arm64
```

Because the app has no embedded native dependencies, the slices come from the
same source and compiler; the usual "one thin dependency spoils the build"
problem of the former PyInstaller path does not apply. That said, Intel macOS
support is winding down, so arm64-only is a defensible choice to state plainly
rather than a bug to hide, and **no universal2 build has been attempted**.

---

## (d) What a real release still needs — explicit checklist

None of the items below exist yet. Until they do, `dist/usbscope-swift.app` stays
**ad-hoc signed, arm64-only and not notarised**, and `docs/index.md` / this file
say exactly that.

- [ ] Developer ID Application certificate issued and installed (only Apple
      Development certs exist on this machine **[ran]**).
- [ ] Real Developer ID signing in `scripts/build-swift-app.sh` — today it does
      `codesign --force --deep --sign -` (ad hoc), with the signing authority
      hard-coded to `-`.
- [ ] Hardened Runtime (`--options runtime`) and a secure timestamp
      (`--timestamp`).
- [ ] A container to notarise (DMG or zip) — the script produces only the `.app`.
- [ ] `xcrun notarytool submit` wired into the build, and `xcrun stapler staple`
      after it.
- [ ] A release pipeline (tag → build → sign → notarise → staple → upload);
      artifacts are currently produced by hand.
- [ ] CI that signs/notarises — `.github/workflows/ci.yml` only runs
      `swift build` + `swift test` and, on `main`, builds/uploads the *unsigned*
      ad-hoc bundle with **no** signing secrets. Distribution signing does not
      happen in CI at all.
- [ ] universal2 or x86_64 builds (current output is arm64-only, verified with
      `file`).
- [ ] A published release of any kind — no DMG, no tag, no binary is uploaded.
- [ ] `SHA256SUMS` for a release artifact; `make checksums` only verifies a
      `dist/SHA256SUMS` if one happens to exist, and nothing generated it.
- [ ] Homebrew tap and cask published (a cask only makes sense once a notarised
      DMG exists in a GitHub Release).
- [ ] The in-process IOKit reader (`Sources/UsbScopeCore/IORegistryReader.swift`)
      verified inside a real sandboxed bundle — it is implemented and tested, and
      it is the default reader, but the sandbox question needs an Apple-issued
      signature plus provisioning profile (see [app-store.md](app-store.md)).
