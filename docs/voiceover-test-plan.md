# VoiceOver smoke-test plan

This is the manual accessibility gate for a signed macOS build. Run with
VoiceOver enabled (`⌘F5`) and with the system text size increased one step.
Record the build identifier, macOS version, and pass/fail result for every
scenario. A failure is a release blocker for the affected workflow.

## Navigation and refresh

1. Launch the app and move through the sidebar with VoiceOver navigation.
   Each section announces its name and selected state.
2. Move to the main table, select a row, and activate its details action.
   The row announces its identity and important state without relying on
   colour.
3. Activate Refresh. VoiceOver announces the busy/progress state, then the
   refreshed result or the source warning. The last good snapshot remains
   available when a later read fails.

## Findings and history

1. Open Security and navigate to a finding. Confirm severity, rule, subject,
   evidence, and the “Open source row” action are all announced.
2. Open History, select an event, and confirm the historical identity and the
   fact that it is not present in the current snapshot are announced.

## Baselines and export

1. Save, load, rename, compare, and clear a baseline using keyboard focus.
   Each operation announces its result or error without losing the current
   snapshot.
2. Open Diagnostics, copy the diagnostic bundle, and export JSON/CSV/report.
   Confirm the confirmation/error text is reachable and that the default
   diagnostic output is redacted.

## Eject and cancellation

1. Open a storage-row context menu, choose Eject, and verify the confirmation
   dialog identifies the volume, device, and mount point.
2. Cancel with the Cancel button and with Escape. Confirm no eject command is
   issued. Repeat and confirm the success or failure result is announced.
3. Repeat the same Escape check for Diagnostics, Command Palette, and the
   detail sheet.

## Release evidence

Attach the VoiceOver rotor/navigation notes and a screen recording or test
log to the release checklist. Automated unit tests cover accessibility labels
and keyboard-safe state transitions, but they cannot replace this signed-app
manual pass.
