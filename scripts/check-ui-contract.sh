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
    local found=0
    if command -v rg >/dev/null 2>&1; then
        rg -q --fixed-strings -- "$pattern" "$file" || found=1
    else
        grep -Fq -- "$pattern" "$file" || found=1
    fi
    if [ "$found" -ne 0 ]; then
        echo "UI contract failed: $description" >&2
        exit 1
    fi
}

forbidden_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    local found=0
    if command -v rg >/dev/null 2>&1; then
        rg -q --fixed-strings -- "$pattern" "$file" && found=1 || true
    else
        grep -Fq -- "$pattern" "$file" && found=1 || true
    fi
    if [ "$found" -ne 0 ]; then
        echo "UI architecture failed: $description" >&2
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
require_pattern "$APP/SnapshotRenderer.swift" "root.dynamicTypeSize(.accessibility3)" "snapshot renderer covers accessibility text size"
require_pattern "$ROOT/scripts/check-swift-accessibility-baselines.sh" "--accessibility-size" "accessibility-size baseline gate remains wired"
require_pattern "$APP/SnapshotRenderer.swift" "arguments.contains(\"--dark\")" "dark appearance rendering remains available"
require_pattern "$ROOT/scripts/check-swift-dark-baselines.sh" "--dark" "dark visual baseline gate remains wired"
require_pattern "$APP/SnapshotRenderer.swift" "arguments.contains(\"--empty\")" "empty-state rendering remains available"
require_pattern "$APP/SnapshotRenderer.swift" "arguments.contains(\"--partial\")" "partial-state rendering remains available"
require_pattern "$ROOT/scripts/check-swift-state-baselines.sh" 'case "$STATE" in empty|partial)' "empty/partial visual baseline gate remains wired"
require_pattern "$APP/AppState.swift" "private var shuttingDown = false" "AppState has a synchronous shutdown gate"
require_pattern "$APP/AppState.swift" "guard !shuttingDown else { return }" "AppState blocks state changes after shutdown"
require_pattern "$APP/AppState.swift" "guard !self.shuttingDown else { return }" "AppState blocks asynchronous work after shutdown"
require_pattern "$APP/UsbScopeApp.swift" "allowsUserCustomization = true" "native toolbar customization remains enabled"
require_pattern "$APP/UsbScopeApp.swift" "autosavesConfiguration = true" "native toolbar configuration remains persistent"
require_pattern "$APP/AppState.swift" "lastHotplugAt" "monitoring records the last hot-plug event"
require_pattern "$APP/Views.swift" "monitoringPollInterval" "monitoring exposes its polling cadence"
require_pattern "$APP/Strings.swift" "monitoringLastEvent" "monitoring details remain localized"
require_pattern "$APP/AppState.swift" "Strings.progressText" "loading progress uses app localization"
require_pattern "$APP/AppState.swift" "language: language" "app table/export paths pass the selected language"
require_pattern "$APP/AppState.swift" "FabricPresentation.rows(snapshot?.thunderboltFabric ?? ThunderboltFabric(), language: language)" "USB4 rows use the selected language"
require_pattern "$APP/Views.swift" "FabricPresentation.rawLinkNote(lang)" "USB4 explanatory text remains localized"
require_pattern "$APP/Views.swift" "Strings.diffDetail(row.detail, lang)" "diff details remain localized"

forbidden_pattern "$APP/AppState.swift" "SnapshotBuilder.collect" "app state must use SnapshotCollectionService"
forbidden_pattern "$APP/UsbScopeApp.swift" "SnapshotBuilder.collect" "app self-tests must use SnapshotCollectionService"
forbidden_pattern "$APP/AppState.swift" "StorageSource()" "app state must use SnapshotCollectionService for storage"
forbidden_pattern "$APP/AppState.swift" "Shell.run" "app state must use CommandExecutionService"
forbidden_pattern "$APP/Views.swift" ".onTapGesture" "interactive rows must use keyboard-accessible buttons"
forbidden_pattern "$APP/Views.swift" "storageStatus.rawValue" "storage health must use localized source status"
forbidden_pattern "$APP/Views.swift" "event.kind.rawValue.capitalized" "event kinds must use localized labels"
forbidden_pattern "$APP/Views.swift" "dataFreshness.rawValue" "freshness status must use localized labels"
forbidden_pattern "$APP/Views.swift" "Text(row.rule)" "security rules must use localized labels"

require_pattern "$SMOKE" "for view in overview ports cables devices thunderbolt power timeline security usb4 diff warnings;" "installed smoke covers all eleven views"

echo "UI contract passed: accessibility hooks, keyboard commands, navigation, and eleven snapshot routes"
