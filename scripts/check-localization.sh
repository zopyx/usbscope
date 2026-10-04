#!/usr/bin/env bash
set -euo pipefail

# Keep user-visible SwiftUI/AppKit chrome behind the typed string table. Stable
# persistence identifiers (for example isColumnVisible(..., "Port")) are not
# presentation strings and are intentionally not matched here.
violations=""
for pattern in \
  '(^|[[:space:](])(Text|Button|Label|Section|TableColumn|DisclosureGroup|Picker)\("[^" ]+' \
  '\.(navigationTitle|help|accessibilityHint|accessibilityValue)\("[^" ]+' \
  '(messageText|informativeText) = "[^" ]+' \
  'addButton\(withTitle: "[^" ]+'; do
  matches="$(rg -n --glob '*.swift' "$pattern" Sources/usbscope-app || true)"
  if [[ -n "${matches}" ]]; then
    violations+="${matches}\n"
  fi
done

if [[ -n "${violations}" ]]; then
  echo "Hardcoded user-visible strings found in Sources/usbscope-app:" >&2
  echo "${violations}" >&2
  exit 1
fi

echo "Localization static check passed."
