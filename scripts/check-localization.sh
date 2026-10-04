#!/usr/bin/env bash
set -euo pipefail

# Keep user-visible SwiftUI/AppKit chrome behind the typed string table. Stable
# persistence identifiers (for example isColumnVisible(..., "Port")) are not
# presentation strings and are intentionally not matched here.
violations="$(rg -n \
  --glob '*.swift' \
  '(^|[.( ])(Text|Button|Label|Section|TableColumn)\("|\.(navigationTitle|help)\("|(messageText|informativeText) = "|addButton\(withTitle: "' \
  Sources/usbscope-app || true)"

if [[ -n "${violations}" ]]; then
  echo "Hardcoded user-visible strings found in Sources/usbscope-app:" >&2
  echo "${violations}" >&2
  exit 1
fi

echo "Localization static check passed."
