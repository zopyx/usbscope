#!/usr/bin/env bash
# Validate the structural and signature invariants of a usbscope app bundle.
set -euo pipefail

APP="${1:?usage: validate-swift-app.sh path/to/usbscope.app [--gatekeeper|--sandbox]}"
GATEKEEPER=0
SANDBOX=0
case "${2:-}" in
  --gatekeeper) GATEKEEPER=1 ;;
  --sandbox) SANDBOX=1 ;;
  "") ;;
  *) echo "unknown validation mode: $2" >&2; exit 2 ;;
esac

[ -d "$APP" ] || { echo "app bundle not found: $APP" >&2; exit 1; }
APP="$(cd "$APP" && pwd)"
INFO="$APP/Contents/Info.plist"
EXEC="$APP/Contents/MacOS/usbscope-app"
[ -f "$INFO" ] || { echo "missing Info.plist" >&2; exit 1; }
[ -x "$EXEC" ] || { echo "missing executable: $EXEC" >&2; exit 1; }

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
[ "$bundle_id" = "com.zopyx.usbscope" ] || { echo "unexpected bundle id: $bundle_id" >&2; exit 1; }
package_type="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$INFO")"
[ "$package_type" = "APPL" ] || { echo "unexpected bundle package type: $package_type" >&2; exit 1; }
min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
[ "$min_os" = "14.4" ] || { echo "unexpected minimum macOS: $min_os" >&2; exit 1; }
marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
[ -n "$marketing_version" ] || { echo "missing marketing version" >&2; exit 1; }
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
case "$build_version" in
  ''|*[!0-9]*|0) echo "CFBundleVersion must be a positive integer: $build_version" >&2; exit 1 ;;
esac
signing_mode="$(/usr/libexec/PlistBuddy -c 'Print :USBScopeSigningMode' "$INFO" 2>/dev/null || true)"
case "$signing_mode" in
  debug|adhoc|developer-id|mas) ;;
  *) echo "USBScopeSigningMode must be debug, adhoc, developer-id, or mas: ${signing_mode:-<missing>}" >&2; exit 1 ;;
esac

# Keep the bundle's executable metadata aligned with the plist. This catches a
# malformed hand-assembled artifact before signature or Gatekeeper checks hide
# the more useful failure.
plist_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
[ "$plist_executable" = "usbscope-app" ] || {
  echo "unexpected bundle executable: $plist_executable" >&2
  exit 1
}

# The product is intentionally one Mach-O. A nested executable or framework
# would need its own signing and entitlement audit before distribution.
nested_code=""
while IFS= read -r -d '' candidate; do
  case "$candidate" in
    */Contents/MacOS/usbscope-app) ;;
    *) nested_code="$candidate"; break ;;
  esac
done < <(find "$APP/Contents" -type f -perm +111 -print0)
[ -z "$nested_code" ] || { echo "unexpected nested executable: ${nested_code#"$APP/"}" >&2; exit 1; }
if find "$APP/Contents" -type d -name '*.framework' -print -quit | grep -q .; then
  echo "unexpected nested framework in app bundle" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
signature_details="$(codesign -dvv "$APP" 2>&1 || true)"
case "$signing_mode" in
  debug|adhoc)
    echo "$signature_details" | grep -q '^Signature=adhoc$' || {
      echo "$signing_mode mode requires an ad-hoc signature" >&2
      exit 1
    }
    ;;
  developer-id)
    echo "$signature_details" | grep -q 'Authority=Developer ID Application:' || {
      echo "developer-id mode requires a Developer ID Application signature" >&2
      exit 1
    }
    ;;
  mas)
    [ "$SANDBOX" -eq 1 ] || { echo "mas mode requires --sandbox validation" >&2; exit 1; }
    ;;
esac
archs="$(lipo -archs "$EXEC" 2>/dev/null || true)"
[ -n "$archs" ] || { echo "cannot inspect executable architectures" >&2; exit 1; }
echo "validated $(basename "$APP"): $bundle_id, version=$marketing_version ($build_version), mode=$signing_mode, macOS >= $min_os, arch=$archs"

entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
has_sandbox=0
if echo "$entitlements" | grep -q 'com.apple.security.app-sandbox'; then has_sandbox=1; fi
if [ "$SANDBOX" -eq 1 ] && [ "$has_sandbox" -ne 1 ]; then
  echo "sandbox validation requested but com.apple.security.app-sandbox is absent" >&2
  exit 1
fi
if [ "$signing_mode" = "mas" ] && [ "$has_sandbox" -ne 1 ]; then
  echo "mas mode is missing com.apple.security.app-sandbox" >&2
  exit 1
fi
if [ "$SANDBOX" -eq 0 ] && [ "$has_sandbox" -eq 1 ]; then
  echo "direct bundle unexpectedly carries com.apple.security.app-sandbox" >&2
  exit 1
fi
echo "  entitlements: $([ "$has_sandbox" -eq 1 ] && echo sandbox || echo direct)"

if [ "$GATEKEEPER" -eq 1 ]; then
  spctl --assess --type execute --verbose=4 "$APP"
fi
