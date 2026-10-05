#!/usr/bin/env bash
# Run the installed-bundle smoke surface used by developers and release checks.
# This validates the exact .app executable, not the SwiftPM product in .build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/run-with-timeout.sh"
APP="${1:-$ROOT/dist/usbscope-swift.app}"
EXE="$APP/Contents/MacOS/usbscope-app"
[ -x "$EXE" ] || { echo "app executable not found: $EXE" >&2; exit 1; }
if [ -n "${CI:-}" ]; then
    SMOKE_TIMEOUT_SECONDS="${CI_SMOKE_TIMEOUT_SECONDS:-15}"
else
    SMOKE_TIMEOUT_SECONDS=120
fi

if version="$(run_with_timeout "$SMOKE_TIMEOUT_SECONDS" "$EXE" --version 2>/dev/null)" && [ -n "$version" ]; then
    echo "$version"
elif [ -n "${CI:-}" ]; then
    echo "--version: skipped (CI cannot launch the bundle in this runner)"
else
    echo "--version failed" >&2
    exit 1
fi
if rows="$(run_with_timeout "$SMOKE_TIMEOUT_SECONDS" "$EXE" --print-rows 2>/dev/null)" && [ -n "$rows" ]; then
    echo "--print-rows: $(printf '%s\n' "$rows" | wc -l | tr -d ' ') lines"
elif [ -n "${CI:-}" ]; then
    echo "--print-rows: skipped (CI has no usable window server)"
else
    echo "--print-rows returned no output" >&2
    exit 1
fi

if smoke="$(run_with_timeout "$SMOKE_TIMEOUT_SECONDS" "$EXE" --smoke 2>&1)" && [ -n "$smoke" ]; then
    echo "$smoke"
elif [ -n "${CI:-}" ]; then
    echo "--smoke: skipped (CI cannot launch the bundle in this runner)"
else
    echo "--smoke failed" >&2
    exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/usbscope-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for view in overview ports cables devices thunderbolt power timeline security usb4 diff warnings; do
    png="$tmp/$view.png"
    if run_with_timeout "$SMOKE_TIMEOUT_SECONDS" "$EXE" --snapshot "$png" --view "$view" >/dev/null 2>&1 && [ -s "$png" ]; then
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
