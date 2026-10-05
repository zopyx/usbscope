#!/usr/bin/env bash
# Compare deterministic fixture renders for an empty or partial-data state.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
FIXTURE="${2:-$ROOT/SwiftTests/Golden/snapshot.json}"
BASELINES="${3:?usage: check-swift-state-baselines.sh APP FIXTURE BASELINES STATE [--dark]}"
STATE="${4:?usage: check-swift-state-baselines.sh APP FIXTURE BASELINES STATE [--dark]}"
DARK=0
[ "${5:-}" = "--dark" ] && DARK=1
case "$STATE" in empty|partial) ;; *) echo "state must be empty or partial: $STATE" >&2; exit 2 ;; esac
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture not found: $FIXTURE" >&2; exit 1; }
[ -d "$BASELINES" ] || { echo "state baseline directory not found: $BASELINES" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-state-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
appearance_flag=()
[ "$DARK" -eq 1 ] && appearance_flag+=(--dark)

for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    actual="$tmp/$view.png"
    expected="$BASELINES/$view.png"
    [ -f "$expected" ] || { echo "missing $STATE baseline: $expected" >&2; exit 1; }
    timeout 120 "$EXE" --snapshot "$actual" --view "$view" --fixture "$FIXTURE" "--$STATE" "${appearance_flag[@]}" >/dev/null 2>&1
    if ! cmp -s "$actual" "$expected"; then
        echo "$STATE$([ "$DARK" -eq 1 ] && echo ' dark') visual baseline mismatch: $view" >&2
        exit 1
    fi
    echo "$STATE$([ "$DARK" -eq 1 ] && echo ' dark') visual baseline passed: $view"
done

echo "$STATE$([ "$DARK" -eq 1 ] && echo ' dark') visual baseline check passed: $BASELINES"
