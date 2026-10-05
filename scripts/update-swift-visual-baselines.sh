#!/usr/bin/env bash
# Regenerate reviewed fixture baselines after an intentional UI change.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
FIXTURE="${2:-$ROOT/SwiftTests/Golden/snapshot.json}"
OUTPUT="${3:-$ROOT/docs/screenshots/fixture-baselines}"
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture not found: $FIXTURE" >&2; exit 1; }
mkdir -p "$OUTPUT"

for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    "$EXE" --snapshot "$OUTPUT/$view.png" --view "$view" --fixture "$FIXTURE" >/dev/null
    echo "updated visual baseline: $OUTPUT/$view.png"
done
