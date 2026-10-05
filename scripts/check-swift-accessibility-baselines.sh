#!/usr/bin/env bash
# Compare deterministic fixture renders at a large macOS accessibility text size.
# This is a headless layout/render gate; signed-app VoiceOver remains a manual gate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/run-with-timeout.sh"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
FIXTURE="${2:-$ROOT/SwiftTests/Golden/snapshot.json}"
BASELINES="${3:-$ROOT/docs/screenshots/fixture-baselines/accessibility3}"
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture not found: $FIXTURE" >&2; exit 1; }
[ -d "$BASELINES" ] || { echo "accessibility baseline directory not found: $BASELINES" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-accessibility-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    actual="$tmp/$view.png"
    expected="$BASELINES/$view.png"
    [ -f "$expected" ] || { echo "missing accessibility baseline: $expected" >&2; exit 1; }
    run_with_timeout 120 "$EXE" --snapshot "$actual" --view "$view" --fixture "$FIXTURE" \
        --accessibility-size >/dev/null 2>&1
    if ! cmp -s "$actual" "$expected"; then
        echo "accessibility visual baseline mismatch: $view" >&2
        exit 1
    fi
    echo "accessibility visual baseline passed: $view"
done

echo "accessibility baseline check passed: $BASELINES"
