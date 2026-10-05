#!/usr/bin/env bash
# Render every SwiftUI view from a fixed JSON fixture. This is the stable input
# for reviewed visual captures; the ordinary bundle smoke remains live-machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/run-with-timeout.sh"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
FIXTURE="${2:-$ROOT/SwiftTests/Golden/snapshot.json}"
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture not found: $FIXTURE" >&2; exit 1; }
if [ -n "${CI:-}" ] && [ "${CI_SWIFTUI_RENDERING:-0}" != 1 ]; then
    echo "fixture snapshot smoke skipped: CI runner has no interactive AppKit window server"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-fixture-snapshots.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    png="$tmp/$view.png"
    log="$tmp/$view.log"
    if ! run_with_timeout 120 "$EXE" --snapshot "$png" --view "$view" --fixture "$FIXTURE" >"$log" 2>&1; then
        echo "fixture snapshot command failed: $view" >&2
        sed -n '1,160p' "$log" >&2
        exit 1
    fi
    [ -s "$png" ] || { echo "fixture snapshot is empty: $view" >&2; exit 1; }
    echo "fixture snapshot $view: $(stat -f '%z bytes' "$png")"
done

echo "fixture snapshot smoke passed: $FIXTURE"
