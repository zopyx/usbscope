#!/usr/bin/env bash
#
# Pack an already-built `dist/usbscope-swift.app` into a macOS disk image:
#
#   dist/usbscope-swift-<version>-macos-<arch>.dmg
#
# Usage
# -----
#   scripts/build-swift-dmg.sh                 # pack + verify + mount-test + checksum
#   scripts/build-swift-dmg.sh --no-verify     # skip the mount/run test
#   scripts/build-swift-dmg.sh --app <path>    # a different .app to pack
#   scripts/build-swift-dmg.sh --volume-name <name>
#
# The image is a compressed read-only UDZO (zlib) DMG whose volume is named
# `usbscope` and holds the `.app` next to an `/Applications` symlink — the usual
# drag-to-install layout. It is built with `hdiutil` alone: no sudo, no Apple
# account and no external tool such as create-dmg/appdmg.
#
# The DMG is *not* a release: the app inside is only ad-hoc signed, so it is
# neither Developer-ID signed nor notarised and Gatekeeper still refuses it on a
# machine that did not build it. This script only packages; the Developer ID /
# notarisation path a real release needs is written down in docs/distribution.md.
#
# The image's sha256 is appended to `dist/SHA256SUMS` (same `<hash>  <name>`
# format as the tarball line) so `make checksums` re-verifies both artifacts.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
PRODUCT_NAME="usbscope-swift"
EXECUTABLE="usbscope-app"

app="$DIST/$PRODUCT_NAME.app"
volume_name="usbscope"
verify=1

while [ $# -gt 0 ]; do
  case "$1" in
    --app) app="${2:?--app needs a path to a .app}"; shift 2 ;;
    --volume-name) volume_name="${2:?--volume-name needs a value}"; shift 2 ;;
    --no-verify) verify=0; shift ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# hdiutil is the whole toolchain; refuse early and loudly if it is missing.
command -v hdiutil >/dev/null 2>&1 || { echo "hdiutil not found — DMG packaging needs macOS" >&2; exit 1; }
echo "+ hdiutil: $(command -v hdiutil)"

[ -d "$app" ] || { echo "no app bundle at ${app#"$ROOT"/} — run scripts/build-swift-app.sh first" >&2; exit 1; }
bundle_exec="$app/Contents/MacOS/$EXECUTABLE"
[ -x "$bundle_exec" ] || { echo "app bundle has no executable at ${bundle_exec#"$ROOT"/}" >&2; exit 1; }

# Version from the bundle itself, so the DMG name matches what is actually inside
# (fall back to main.swift if the plist cannot be read).
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$version" ]; then
  version="$(sed -n 's/^let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/usbscope/main.swift" | head -1)"
fi
[ -n "$version" ] || { echo "cannot determine the bundle version" >&2; exit 1; }

# Architecture label from the binary that is packed: a fat Mach-O is universal2,
# a thin one is its single architecture. This keeps the DMG name honest for a
# native and a `--universal` bundle alike.
archs="$(lipo -archs "$bundle_exec" 2>/dev/null || true)"
case "$archs" in
  *x86_64*arm64*|*arm64*x86_64*) arch="universal2" ;;
  *arm64*) arch="arm64" ;;
  *x86_64*) arch="x86_64" ;;
  *) arch="$(uname -m)" ;;
esac

dmg="$DIST/$PRODUCT_NAME-$version-macos-$arch.dmg"

# Everything is staged in a private temp dir. The trap tears the staging dir down
# and detaches the test mount even on failure, so no loop device or staged file is
# left behind.
staging="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-dmg.XXXXXX")"
mount_point=""
cleanup() {
  if [ -n "$mount_point" ] && [ -d "$mount_point" ]; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || true
  fi
  [ -n "$staging" ] && rm -rf "$staging"
}
trap cleanup EXIT

stage="$staging/stage"
mkdir -p "$stage"
# ditto copies a bundle faithfully (resource forks, extended attributes); cp -R
# does not always preserve them.
echo "\$ ditto ${app#"$ROOT"/} $PRODUCT_NAME.app"
ditto "$app" "$stage/$PRODUCT_NAME.app"
ln -s /Applications "$stage/Applications"

[ -f "$dmg" ] && { echo "+ remove ${dmg#"$ROOT"/}"; rm -f "$dmg"; }

# One hdiutil pass builds the final compressed, read-only image straight from the
# staged folder: `-format UDZO` is zlib-compressed + read-only, exactly what a
# `hdiutil convert ... -format UDZO` pass would end up with.
echo "\$ hdiutil create -volname $volume_name -srcfolder <staged> -ov -format UDZO ${dmg#"$ROOT"/}"
hdiutil create -volname "$volume_name" -srcfolder "$stage" -ov -format UDZO "$dmg"

echo "\$ hdiutil verify ${dmg#"$ROOT"/}"
hdiutil verify "$dmg"

# The mount test is the real proof that the image works: mount it, check the two
# expected entries, run the binary from the mounted copy, detach.
if [ "$verify" -eq 1 ]; then
  mount_point="$staging/mnt"
  mkdir -p "$mount_point"
  echo "\$ hdiutil attach ${dmg#"$ROOT"/} -nobrowse -readonly -mountpoint <staged mount>"
  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point"

  [ -d "$mount_point/$PRODUCT_NAME.app" ] || { echo "mounted image has no $PRODUCT_NAME.app" >&2; exit 1; }
  [ -L "$mount_point/Applications" ] || { echo "mounted image has no /Applications symlink" >&2; exit 1; }
  echo "  mounted volume contents: $(cd "$mount_point" && ls | tr '\n' ' ')"

  line="$("$mount_point/$PRODUCT_NAME.app/Contents/MacOS/$EXECUTABLE" --version 2>/dev/null | head -1 || true)"
  if [ -z "$line" ]; then
    echo "app inside the mounted image failed \`--version\`" >&2
    exit 1
  fi
  echo "  mounted copy --version → $line"

  echo "\$ hdiutil detach <staged mount>"
  hdiutil detach "$mount_point" >/dev/null
  mount_point=""
else
  echo "mount test skipped (--no-verify)"
fi

# Append this image's checksum to dist/SHA256SUMS in the same `<hash>  <name>`
# format the tarball line uses, so `make checksums` verifies both artifacts. An
# existing line for the same file is dropped first, so re-running does not
# duplicate it — and the tarball's line is left untouched.
base="$(basename "$dmg")"
line="$(cd "$DIST" && shasum -a 256 "$base")"
sums="$DIST/SHA256SUMS"
if [ -f "$sums" ]; then
  grep -v "[[:space:]]$base\$" "$sums" > "$sums.tmp" 2>/dev/null || true
  mv "$sums.tmp" "$sums"
fi
printf '%s\n' "$line" >> "$sums"

echo
echo "${dmg#"$ROOT"/}  ($(awk -v b="$(stat -f%z "$dmg")" 'BEGIN {printf "%.1f", b/1048576}') MiB)"
cat "$sums"
