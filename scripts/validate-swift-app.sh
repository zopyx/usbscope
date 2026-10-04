#!/usr/bin/env bash
# Validate the structural and signature invariants of a usbscope app bundle.
set -euo pipefail

APP="${1:?usage: validate-swift-app.sh path/to/usbscope.app [--gatekeeper]}"
GATEKEEPER=0
[ "${2:-}" = "--gatekeeper" ] && GATEKEEPER=1

[ -d "$APP" ] || { echo "app bundle not found: $APP" >&2; exit 1; }
INFO="$APP/Contents/Info.plist"
EXEC="$APP/Contents/MacOS/usbscope-app"
[ -f "$INFO" ] || { echo "missing Info.plist" >&2; exit 1; }
[ -x "$EXEC" ] || { echo "missing executable: $EXEC" >&2; exit 1; }

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
[ "$bundle_id" = "com.zopyx.usbscope" ] || { echo "unexpected bundle id: $bundle_id" >&2; exit 1; }
min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
[ "$min_os" = "14.4" ] || { echo "unexpected minimum macOS: $min_os" >&2; exit 1; }
marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
[ -n "$marketing_version" ] || { echo "missing marketing version" >&2; exit 1; }
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
case "$build_version" in
  ''|*[!0-9]*|0) echo "CFBundleVersion must be a positive integer: $build_version" >&2; exit 1 ;;
esac

# Keep the bundle's executable metadata aligned with the plist. This catches a
# malformed hand-assembled artifact before signature or Gatekeeper checks hide
# the more useful failure.
plist_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
[ "$plist_executable" = "usbscope-app" ] || {
  echo "unexpected bundle executable: $plist_executable" >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$APP"
archs="$(lipo -archs "$EXEC" 2>/dev/null || true)"
[ -n "$archs" ] || { echo "cannot inspect executable architectures" >&2; exit 1; }
echo "validated $(basename "$APP"): $bundle_id, version=$marketing_version ($build_version), macOS >= $min_os, arch=$archs"

if [ "$GATEKEEPER" -eq 1 ]; then
  spctl --assess --type execute --verbose=4 "$APP"
fi
