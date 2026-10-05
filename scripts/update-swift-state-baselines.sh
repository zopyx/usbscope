#!/usr/bin/env bash
# Regenerate deterministic empty or partial-data fixture baselines.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
FIXTURE="${2:-$ROOT/SwiftTests/Golden/snapshot.json}"
OUTPUT="${3:?usage: update-swift-state-baselines.sh APP FIXTURE OUTPUT STATE [--dark]}"
STATE="${4:?usage: update-swift-state-baselines.sh APP FIXTURE OUTPUT STATE [--dark]}"
DARK=0
[ "${5:-}" = "--dark" ] && DARK=1
case "$STATE" in empty|partial) ;; *) echo "state must be empty or partial: $STATE" >&2; exit 2 ;; esac
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture not found: $FIXTURE" >&2; exit 1; }
mkdir -p "$OUTPUT"
appearance_flag=()
[ "$DARK" -eq 1 ] && appearance_flag+=(--dark)

for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    "$EXE" --snapshot "$OUTPUT/$view.png" --view "$view" --fixture "$FIXTURE" "--$STATE" "${appearance_flag[@]}" >/dev/null
    echo "updated $STATE$([ "$DARK" -eq 1 ] && echo ' dark') baseline: $OUTPUT/$view.png"
done
