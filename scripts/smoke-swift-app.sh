#!/usr/bin/env bash
# Run the installed-bundle smoke surface used by developers and release checks.
# This validates the exact .app executable, not the SwiftPM product in .build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }

"$EXE" --version
if rows="$($EXE --print-rows 2>/dev/null)" && [ -n "$rows" ]; then
    echo "--print-rows: $(printf '%s\n' "$rows" | wc -l | tr -d ' ') lines"
elif [ -n "${CI:-}" ]; then
    echo "--print-rows: skipped (CI has no usable window server)"
else
    echo "--print-rows returned no output" >&2
    exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    png="$tmp/$view.png"
    if "$EXE" --snapshot "$png" --view "$view" >/dev/null 2>&1 && [ -s "$png" ]; then
        echo "--snapshot $view: $(stat -f '%z bytes' "$png")"
    elif [ -n "${CI:-}" ]; then
        echo "--snapshot $view: skipped (CI has no usable window server)"
    else
        echo "--snapshot $view failed" >&2
        exit 1
    fi
done

codesign --verify --deep --strict "$APP"
echo "bundle smoke passed: $APP"
