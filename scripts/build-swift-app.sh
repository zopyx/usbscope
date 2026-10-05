#!/usr/bin/env bash
#
# Build `dist/usbscope-swift.app` — the SwiftUI app as a real macOS app bundle.
#
#   swift build -c release --product usbscope-app        compile the product
#   dist/usbscope-swift.app/Contents/MacOS/usbscope-app  the release binary
#   dist/usbscope-swift.app/Contents/Info.plist          bundle metadata
#   dist/usbscope-swift.app/Contents/Resources/*.icns    the icon, when it exists
#
# Usage
# -----
#   scripts/build-swift-app.sh              # build + bundle + sign + verify + tar
#   scripts/build-swift-app.sh --no-sign    # skip the ad-hoc codesign
#   scripts/build-swift-app.sh --debug      # debug configuration
#   scripts/build-swift-app.sh --no-verify  # do not run the bundled binary
#   scripts/build-swift-app.sh --no-archive # only the .app, no tarball/checksum
#   scripts/build-swift-app.sh --universal  # build arm64 + x86_64 (fat), not native-only
#   scripts/build-swift-app.sh --entitlements FILE # apply entitlements for a signed mode
#   scripts/build-swift-app.sh --signing-mode MODE # debug|adhoc|developer-id|mas
#
# `--universal` adds `--arch arm64 --arch x86_64` to the `swift build`, so the
# produced executable is a fat Mach-O (checked with `lipo`); without it the build
# stays *native-only*, exactly as before. The archive name then says `universal2`
# instead of the host architecture. A universal bundle is still signed *ad hoc*
# (`codesign -s -`), so it is neither Developer-ID signed nor notarised either.
#
# On top of the bundle it writes the archive a release would hand out
# (`dist/usbscope-swift-<version>-macos-<arch>-<signing-mode>.tar.gz`) and `dist/SHA256SUMS` for
# it, which `make checksums` re-verifies. `scripts/build-swift-dmg.sh` packs the
# same bundle into a DMG.
#
# Direct bundles are signed ad hoc by default and deliberately do not carry the
# Mac App Store sandbox entitlement. The MAS wrapper supplies that entitlement
# together with the provisioning profile; a credentialed direct build may pass
# `--entitlements` explicitly. An ad-hoc signature is a valid self-signature, but
# neither Developer-ID signed nor notarised, so a download is still stopped by
# Gatekeeper. What a real release additionally needs — Developer ID, hardened
# runtime, `notarytool`, `stapler` — is written down in docs/distribution.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
BUNDLE_ID="com.zopyx.usbscope"
EXECUTABLE="usbscope-app"
PRODUCT="usbscope-app"
ICON_SOURCE="$ROOT/assets/icon/usbscope.icns"
MIN_MACOS="14.4"

configuration="release"
name="usbscope-swift"
icon="$ICON_SOURCE"
sign=1
verify=1
archive=1
universal=0
signing_identity="${CODESIGN_IDENTITY:--}"
signing_mode=""
notarize=0
notary_profile="${NOTARY_PROFILE:-}"
entitlements=""

while [ $# -gt 0 ]; do
  case "$1" in
    --configuration) configuration="${2:?--configuration needs release|debug}"; shift 2 ;;
    --debug) configuration="debug"; shift ;;
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    --no-icon) icon=""; shift ;;
    --no-sign) sign=0; shift ;;
    --no-verify) verify=0; shift ;;
    --no-archive) archive=0; shift ;;
    --universal) universal=1; shift ;;
    --identity) signing_identity="${2:?--identity needs a codesign identity}"; shift 2 ;;
    --signing-mode) signing_mode="${2:?--signing-mode needs debug|adhoc|developer-id|mas}"; shift 2 ;;
    --entitlements) entitlements="${2:?--entitlements needs a plist path}"; shift 2 ;;
    --notarize) notarize=1; shift ;;
    --notary-profile) notary_profile="${2:?--notary-profile needs a keychain profile}"; shift 2 ;;
    -h|--help) sed -n '10,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Keep the old flags compatible while making the release intent explicit in the
# artifact. An identity implies Developer ID; a debug configuration without an
# identity is a debug ad-hoc build; the remaining default is a test ad-hoc build.
if [ -z "$signing_mode" ]; then
  if [ "$configuration" = "debug" ] && [ "$signing_identity" = "-" ]; then
    signing_mode="debug"
  elif [ "$signing_identity" = "-" ]; then
    signing_mode="adhoc"
  else
    signing_mode="developer-id"
  fi
fi

case "$signing_mode" in
  debug)
    [ "$configuration" = "debug" ] || { echo "debug signing mode requires --debug/--configuration debug" >&2; exit 2; }
    [ "$signing_identity" = "-" ] || { echo "debug signing mode requires ad-hoc signing" >&2; exit 2; }
    ;;
  adhoc)
    [ "$signing_identity" = "-" ] || { echo "adhoc signing mode cannot use an Apple identity" >&2; exit 2; }
    ;;
  developer-id)
    [ "$signing_identity" != "-" ] || { echo "developer-id signing mode requires --identity or CODESIGN_IDENTITY" >&2; exit 2; }
    ;;
  mas)
    [ "$sign" -eq 0 ] || { echo "mas mode is signed by scripts/build-swift-mas-pkg.sh; use --no-sign" >&2; exit 2; }
    [ "$archive" -eq 0 ] || { echo "mas mode does not produce a direct-distribution archive" >&2; exit 2; }
    ;;
  *) echo "unknown signing mode: $signing_mode (expected debug, adhoc, developer-id, or mas)" >&2; exit 2 ;;
esac

if [ "$notarize" -eq 1 ] && [ "$archive" -eq 0 ]; then
  echo "--notarize requires archive output (omit --no-archive)" >&2
  exit 2
fi

if [ -n "$entitlements" ]; then
  [ -f "$entitlements" ] || { echo "entitlements file not found: $entitlements" >&2; exit 1; }
  if [ "$signing_identity" = "-" ]; then
    echo "sandbox or distribution entitlements require an Apple-issued signing identity; use --no-sign for the MAS wrapper" >&2
    exit 2
  fi
fi

# The version lives in the Swift CLI's main.swift.
version="$(sed -n 's/^let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/usbscope/main.swift" | head -1)"
if [ -z "$version" ]; then
  echo "cannot determine the package version (Sources/usbscope/main.swift)" >&2
  exit 1
fi

# Keep the marketing version (`CFBundleShortVersionString`) separate from the
# numeric build submitted to Apple. CI supplies GITHUB_RUN_NUMBER; local builds
# use the repository revision count, which is monotonic within that checkout.
# An explicit BUILD_NUMBER is available to release automation.
if [ -n "${BUILD_NUMBER:-}" ]; then
  build_number="$BUILD_NUMBER"
elif [ -n "${GITHUB_RUN_NUMBER:-}" ]; then
  build_number="$GITHUB_RUN_NUMBER"
elif command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-list --count HEAD >/dev/null 2>&1; then
  build_number="$(git -C "$ROOT" rev-list --count HEAD)"
else
  build_number="1"
fi
case "$build_number" in
  ''|*[!0-9]*|0) echo "BUILD_NUMBER must be a positive integer (got '$build_number')" >&2; exit 2 ;;
esac

# Native-only by default; --universal adds both slices so the linker emits a fat
# Mach-O. `--show-bin-path` accepts the same --arch flags and still names the one
# output directory the fat binary lands in.
build_args=(build -c "$configuration" --product "$PRODUCT")
if [ "$universal" -eq 1 ]; then
  build_args+=(--arch arm64 --arch x86_64)
fi

echo "usbscope-swift $version ($configuration)"
echo "\$ swift ${build_args[*]}"
swift "${build_args[@]}"

bin_path="$(swift "${build_args[@]}" --show-bin-path | tail -1)"
binary="$bin_path/$EXECUTABLE"
if [ ! -x "$binary" ]; then
  echo "swift build did not produce an executable at $binary" >&2
  exit 1
fi

bundle="$DIST/$name.app"
[ -d "$bundle" ] && { echo "+ remove ${bundle#"$ROOT"/}"; rm -rf "$bundle"; }
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

echo "+ copy $binary -> ${bundle#"$ROOT"/}/Contents/MacOS/$EXECUTABLE"
cp -p "$binary" "$bundle/Contents/MacOS/$EXECUTABLE"
chmod +x "$bundle/Contents/MacOS/$EXECUTABLE"

# A universal build that came out thin is a broken artifact, not a warning: say
# which architectures are actually inside and fail if the fat binary is missing.
if [ "$universal" -eq 1 ]; then
  echo "\$ lipo -info ${bundle#"$ROOT"/}/Contents/MacOS/$EXECUTABLE"
  lipo -info "$bundle/Contents/MacOS/$EXECUTABLE"
  archs="$(lipo -archs "$bundle/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true)"
  case "$archs" in
    *x86_64*arm64*|*arm64*x86_64*) echo "  universal: $archs" ;;
    *) echo "universal build did not produce a fat binary (lipo -archs: ${archs:-<none>})" >&2; exit 1 ;;
  esac
fi

icon_name=""
if [ -n "$icon" ] && [ -f "$icon" ]; then
  echo "+ copy ${icon#"$ROOT"/} -> ${bundle#"$ROOT"/}/Contents/Resources/$(basename "$icon")"
  cp -p "$icon" "$bundle/Contents/Resources/"
  icon_name="$(basename "$icon")"
else
  echo "+ no icon (assets/icon/usbscope.icns not found)"
fi

# Two indented lines (empty when there is no icon, which leaves a blank line).
icon_entry=""
if [ -n "$icon_name" ]; then
  icon_entry="  <key>CFBundleIconFile</key>
  <string>$icon_name</string>"
fi

# ITSAppUsesNonExemptEncryption: App Store Connect asks about export compliance on
# every upload; answering here keeps the question out of the submission flow.
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>usbscope</string>
  <key>CFBundleDisplayName</key>
  <string>usbscope</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build_number</string>
  <key>USBScopeSigningMode</key>
  <string>$signing_mode</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key>
  <string>MIT licensed</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
$icon_entry
</dict>
</plist>
PLIST

# plutil is the system's own plist parser: if this fails the bundle is broken and
# there is no point signing it.
plutil -lint "$bundle/Contents/Info.plist" >/dev/null
echo "+ write ${bundle#"$ROOT"/}/Contents/Info.plist (plutil --lint OK)"

if [ "$sign" -eq 1 ]; then
  if command -v codesign >/dev/null 2>&1; then
    sign_args=(--force --deep --sign "$signing_identity" --identifier "$BUNDLE_ID")
    if [ "$signing_identity" != "-" ]; then sign_args+=(--options runtime); fi
    echo "\$ codesign --force --deep --sign $signing_identity --identifier $BUNDLE_ID $name.app"
    if [ -n "$entitlements" ]; then
      codesign "${sign_args[@]}" --entitlements "$entitlements" "$bundle"
    else
      codesign "${sign_args[@]}" "$bundle"
    fi
    # The verification is not optional: a bundle whose signature does not check
    # out is a broken artifact.
    codesign --verify --verbose=2 "$bundle"
    if [ "$signing_mode" = "developer-id" ]; then
      signature_details="$(codesign -dvv "$bundle" 2>&1 || true)"
      echo "$signature_details" | grep -q 'Authority=Developer ID Application:' || {
        echo "developer-id mode did not produce a Developer ID Application signature" >&2
        exit 1
      }
      echo "Developer ID signed (codesign --verify OK)"
    else
      echo "ad-hoc signed (codesign --verify OK)"
    fi
  else
    echo "codesign not found — skipped"
  fi
else
  echo "signature skipped (--no-sign)"
fi

if [ "$verify" -eq 1 ]; then
  exe="$bundle/Contents/MacOS/$EXECUTABLE"
  [ -x "$exe" ] || { echo "bundle has no executable at $exe" >&2; exit 1; }

  line="$("$exe" --version 2>/dev/null | head -1 || true)"
  if [ -z "$line" ]; then
    if [ -n "${CI:-}" ]; then
      echo "  --version → skipped (headless CI runner has no window server)"
    else
      echo "bundled app failed \`--version\`" >&2
      exit 1
    fi
  else
    echo "  --version → $line"
  fi

  # --print-rows is the app's headless data path; it needs a window server, so its
  # absence is reported instead of failing the build on a headless machine.
  rows="$(timeout 120 "$exe" --print-rows 2>/dev/null || true)"
  if [ -n "$rows" ]; then
    echo "  --print-rows → $(printf '%s\n' "$rows" | wc -l | tr -d ' ') lines (live data path OK)"
  else
    echo "  --print-rows → skipped (no window server session)"
  fi
  echo "  Info.plist: $BUNDLE_ID $version (min macOS $MIN_MACOS)"
fi

if [ "$sign" -eq 1 ]; then
  if [ -n "$entitlements" ] && grep -q 'com.apple.security.app-sandbox' "$entitlements"; then
    "$ROOT/scripts/validate-swift-app.sh" "$bundle" --sandbox
  else
    "$ROOT/scripts/validate-swift-app.sh" "$bundle"
  fi
fi

size="$(du -sk "$bundle" | awk '{printf "%.1f", $1/1024}')"
echo
echo "${bundle#"$ROOT"/}  (${size} MiB, usbscope)"

# A directory is not something you hand out, so the bundle is also packed into the
# archive a release would ship, and that archive is what gets a checksum. `make
# checksums` re-verifies it later; nothing else writes a SHA256SUMS.
if [ "$archive" -eq 1 ]; then
  if [ "$universal" -eq 1 ]; then
    arch="universal2"
  else
    arch="$(uname -m)"
  fi
  tarball="$DIST/$name-$version-macos-$arch-$signing_mode.tar.gz"
  if [ "$notarize" -eq 1 ]; then
    [ "$signing_identity" != "-" ] || { echo "--notarize requires --identity" >&2; exit 2; }
    [ -n "$notary_profile" ] || { echo "--notarize requires --notary-profile or NOTARY_PROFILE" >&2; exit 2; }
    command -v xcrun >/dev/null 2>&1 || { echo "xcrun not found; cannot notarize" >&2; exit 1; }
    notarization_zip="$DIST/$name-$version-macos-$arch-notarization.zip"
    echo "+ create notarization input $(basename "$notarization_zip")"
    ditto -c -k --keepParent "$bundle" "$notarization_zip"
    echo "+ submit notarization (profile $notary_profile)"
    xcrun notarytool submit "$notarization_zip" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$bundle"
    xcrun stapler validate "$bundle"
    rm -f "$notarization_zip"
  fi
  echo "\$ tar -czf ${tarball#"$ROOT"/} -C dist $name.app"
  tar -czf "$tarball" -C "$DIST" "$name.app"
  ( cd "$DIST" && shasum -a 256 "$(basename "$tarball")" > SHA256SUMS )
  echo "$(basename "$tarball")  ($(awk -v b="$(stat -f%z "$tarball")" 'BEGIN {printf "%.1f", b/1048576}') MiB)"
  cat "$DIST/SHA256SUMS"
fi
