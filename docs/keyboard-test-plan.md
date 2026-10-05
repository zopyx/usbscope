# Keyboard-only test plan

This is the release checklist for the workflows that must be usable without a
pointing device. Run it against the signed app bundle with a fixture-backed
snapshot available, then repeat the refresh and failure cases on a live Mac.
Record the build number, macOS version, keyboard layout, and pass/fail result.

## Navigation and filtering

1. Focus the sidebar with Tab and move between sections with Up/Down. Use
   Return to activate Ports, Cables, Devices, Thunderbolt, Power, Timeline,
   Security, USB4, Diff, and Warnings; confirm the selected view is announced.
2. Use `⌘1`–`⌘9` for the first nine views and `⌘K` followed by the view name for
   Warnings. Confirm focus returns to the main content.
3. Tab to the search field, type a term, and use Shift-Tab to return to the
   table. Clear the term with `⌘A` and Delete; verify filtering never changes
   the underlying snapshot.
4. Tab to the filter preset and use Left/Right, then Return. Confirm All,
   HID, Storage, and Connected update the visible rows.

## Selection, details, and refresh

1. Focus a table, use Up/Down to select a row, and press `⌘D`. Confirm the
   detail sheet opens, Return activates its primary action, and Escape closes
   it without changing the selection.
2. Press `⌘R` while idle and while a read is in progress. Confirm the command
   is disabled during collection and the final status remains visible.
3. Open Command Palette with `⌘K`, type a command, press Return, and cancel
   with Escape. Confirm a cancelled palette makes no state change.

## Baselines, copy, and export

1. Use the toolbar/menu commands to save, load, rename, compare, and clear a
   baseline. Use Return for the default action and Escape for every cancel
   path; the current snapshot must remain visible after a failed load.
2. With a row selected, press `⌘C` and then `⇧⌘C` with no selection. Confirm
   the selected/all-row clipboard paths produce the expected TSV.
3. Press `⇧⌘J` for JSON copy, `⌘S` for JSON export, `⇧⌘S` for CSV export, and
   `⇧⌘E` for a report. Cancel each save panel with Escape and confirm no
   partial file is left behind.

## Security and eject safety

1. Navigate to Security, focus a finding, and press Return on its details/source
   action. Confirm the evidence disclosure and source-row navigation are
   reachable by keyboard.
2. Focus a storage row, open its context menu with Shift-F10 (or the keyboard
   menu key), choose Eject, and confirm the dialog. Escape must select the
   safe Cancel path; no eject command may run.
3. Repeat with the Eject button focused. Confirm disabled rows expose a reason
   and cannot invoke the command.

The automated UI-contract check verifies that the command shortcuts and
accessibility hooks remain present. This checklist verifies focus order,
native Table behavior, save-panel cancellation, and dialog defaults on a signed
macOS build; it therefore remains a manual release gate.
