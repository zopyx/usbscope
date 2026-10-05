#!/usr/bin/env bash
# Verify the source-level UI contract that can run in SwiftPM CI without a
# window server. Interactive VoiceOver/XCUITest coverage remains a signed-app
# release gate; this catches accidental removal of the corresponding hooks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/Sources/usbscope-app"
SMOKE="$ROOT/scripts/smoke-swift-app.sh"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    if ! rg -q --fixed-strings -- "$pattern" "$file"; then
        echo "UI contract failed: $description" >&2
        exit 1
    fi
}

require_pattern "$APP/Views.swift" ".accessibilityLabel(text.text)" "table cells expose their text"
require_pattern "$APP/Views.swift" ".accessibilityElement(children: .combine)" "dynamic rows expose combined VoiceOver elements"
require_pattern "$APP/Views.swift" "struct SourceHealthControl: View" "source-health control remains present"
require_pattern "$APP/Views.swift" "struct EmptyState: View" "shared actionable empty state remains present"
require_pattern "$APP/UsbScopeApp.swift" ".keyboardShortcut(\"r\", modifiers: .command)" "refresh has a command shortcut"
require_pattern "$APP/UsbScopeApp.swift" ".keyboardShortcut(\"c\", modifiers: .command)" "copy-selected has a command shortcut"
require_pattern "$APP/UsbScopeApp.swift" ".keyboardShortcut(\"d\", modifiers: .command)" "details has a command shortcut"
require_pattern "$APP/UsbScopeApp.swift" ".keyboardShortcut(\"s\", modifiers: .command)" "JSON export has a command shortcut"
require_pattern "$APP/UsbScopeApp.swift" ".keyboardShortcut(\"k\", modifiers: [.command])" "command palette has a command shortcut"
require_pattern "$APP/UsbScopeApp.swift" "ForEach(AppView.allCases)" "every view remains reachable from the command menus"

require_pattern "$SMOKE" "for view in ports cables devices thunderbolt power timeline security usb4 diff warnings;" "installed smoke covers all ten views"

echo "UI contract passed: accessibility hooks, keyboard commands, navigation, and ten snapshot routes"
