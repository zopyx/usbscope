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
#   scripts/build-swift-app.sh              # build + bundle + sign + verify
#   scripts/build-swift-app.sh --no-sign    # skip the ad-hoc codesign
#   scripts/build-swift-app.sh --debug      # debug configuration
#   scripts/build-swift-app.sh --no-verify  # do not run the bundled binary
#
# Like every bundle this repository builds, the signature is *ad-hoc*
# (`codesign -s -`): a valid self-signature, but neither Developer-ID signed nor
# notarised, so a download is still stopped by Gatekeeper. What a real release
# additionally needs — Developer ID, hardened runtime, `notarytool`, `stapler` —
# and everything this script does *not* do is written down in docs/distribution.md.

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

while [ $# -gt 0 ]; do
  case "$1" in
    --configuration) configuration="${2:?--configuration needs release|debug}"; shift 2 ;;
    --debug) configuration="debug"; shift ;;
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    --no-icon) icon=""; shift ;;
    --no-sign) sign=0; shift ;;
    --no-verify) verify=0; shift ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# The version lives in the Swift CLI's main.swift.
version="$(sed -n 's/^let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/usbscope/main.swift" | head -1)"
if [ -z "$version" ]; then
  echo "cannot determine the package version (Sources/usbscope/main.swift)" >&2
  exit 1
fi

echo "usbscope-swift $version ($configuration)"
echo "\$ swift build -c $configuration --product $PRODUCT"
swift build -c "$configuration" --product "$PRODUCT"

bin_path="$(swift build -c "$configuration" --show-bin-path | tail -1)"
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

icon_name=""
if [ -n "$icon" ] && [ -f "$icon" ]; then
  echo "+ copy ${icon#"$ROOT"/} -> ${bundle#"$ROOT"/}/Contents/Resources/$(basename "$icon")"
  cp -p "$icon" "$bundle/Contents/Resources/"
  icon_name="$(basename "$icon")"
else
  echo "+ no icon (assets/icon/usbscope.icns not found)"
fi

icon_entry=""
if [ -n "$icon_name" ]; then
  icon_entry="	<key>CFBundleIconFile</key>
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
	<string>$version</string>
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
    echo "\$ codesign --force --deep --sign - --identifier $BUNDLE_ID $name.app"
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$bundle"
    # The verification is not optional: a bundle whose signature does not check
    # out is a broken artifact.
    codesign --verify --verbose=2 "$bundle"
    echo "ad-hoc signed (codesign --verify OK)"
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
    echo "bundled app failed \`--version\`" >&2
    exit 1
  fi
  echo "  --version → $line"

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

size="$(du -sk "$bundle" | awk '{printf "%.1f", $1/1024}')"
echo
echo "${bundle#"$ROOT"/}  (${size} MiB, usbscope)"
