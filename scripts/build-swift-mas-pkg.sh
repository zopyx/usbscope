#!/usr/bin/env bash
# Build and validate a sandboxed Mac App Store installer package.
#
# This script deliberately requires all signing inputs explicitly. It never
# falls back to ad-hoc signing, because an ad-hoc bundle cannot answer the
# sandbox and provisioning checks that matter for App Store submission.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/usbscope-swift.app"
PROFILE=""
APP_IDENTITY="${MAS_APP_IDENTITY:-}"
INSTALLER_IDENTITY="${MAS_INSTALLER_IDENTITY:-}"
CONFIGURATION="release"
PKG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile needs a .provisionprofile}"; shift 2 ;;
    --app-identity) APP_IDENTITY="${2:?--app-identity needs an Apple Distribution identity}"; shift 2 ;;
    --installer-identity) INSTALLER_IDENTITY="${2:?--installer-identity needs an installer identity}"; shift 2 ;;
    --configuration) CONFIGURATION="${2:?--configuration needs release or debug}"; shift 2 ;;
    --output) PKG="${2:?--output needs a .pkg path}"; shift 2 ;;
    -h|--help)
      sed -n '1,24p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$PROFILE" ] || { echo "--profile is required" >&2; exit 2; }
[ -f "$PROFILE" ] || { echo "provisioning profile not found: $PROFILE" >&2; exit 1; }
[ -n "$APP_IDENTITY" ] || { echo "--app-identity or MAS_APP_IDENTITY is required" >&2; exit 2; }
[ -n "$INSTALLER_IDENTITY" ] || { echo "--installer-identity or MAS_INSTALLER_IDENTITY is required" >&2; exit 2; }
command -v codesign >/dev/null 2>&1 || { echo "codesign is required" >&2; exit 1; }
command -v productbuild >/dev/null 2>&1 || { echo "productbuild is required" >&2; exit 1; }
command -v pkgutil >/dev/null 2>&1 || { echo "pkgutil is required" >&2; exit 1; }

mkdir -p "$DIST"
"$ROOT/scripts/build-swift-app.sh" --configuration "$CONFIGURATION" --no-sign --no-archive --no-verify

cp -p "$PROFILE" "$APP/Contents/embedded.provisionprofile"
codesign --force --timestamp --options runtime \
  --entitlements "$ROOT/assets/entitlements/usbscope.entitlements" \
  --sign "$APP_IDENTITY" --identifier com.zopyx.usbscope "$APP"
codesign --verify --strict --verbose=2 "$APP"

"$ROOT/scripts/validate-swift-app.sh" "$APP" --sandbox

entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
echo "$entitlements" | grep -q 'com.apple.security.app-sandbox' || {
  echo "signed app is missing com.apple.security.app-sandbox" >&2
  exit 1
}
if echo "$entitlements" | grep -q 'com.apple.security.network.client'; then
  echo "unexpected network client entitlement in sandboxed app" >&2
  exit 1
fi

if [ -z "$PKG" ]; then
  version="$(sed -n 's/^let version = "\([^\"]*\)".*/\1/p' "$ROOT/Sources/usbscope/main.swift" | head -1)"
  PKG="$DIST/usbscope-$version-mas.pkg"
fi
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG"
echo "Mac App Store package validated: ${PKG#"$ROOT"/}"
