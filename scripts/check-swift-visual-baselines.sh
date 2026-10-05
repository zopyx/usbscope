#!/usr/bin/env bash
# Compare deterministic fixture renders with the reviewed PNG baselines.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/run-with-timeout.sh"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
FIXTURE="${2:-$ROOT/SwiftTests/Golden/snapshot.json}"
BASELINES="${3:-$ROOT/docs/screenshots/fixture-baselines}"
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture not found: $FIXTURE" >&2; exit 1; }
[ -d "$BASELINES" ] || { echo "visual baseline directory not found: $BASELINES" >&2; exit 1; }
if [ -n "${CI:-}" ] && [ "${CI_SWIFTUI_RENDERING:-0}" != 1 ]; then
    echo "light visual baselines skipped: CI runner has no interactive AppKit window server"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-visual-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    actual="$tmp/$view.png"
    expected="$BASELINES/$view.png"
    [ -f "$expected" ] || { echo "missing visual baseline: $expected" >&2; exit 1; }
    run_with_timeout 120 "$EXE" --snapshot "$actual" --view "$view" --fixture "$FIXTURE" >/dev/null 2>&1
    if ! cmp -s "$actual" "$expected"; then
        echo "visual baseline mismatch: $view" >&2
        exit 1
    fi
    echo "visual baseline passed: $view"
done

echo "visual baseline check passed: $BASELINES"
