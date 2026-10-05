# usbscope Mac App Review

## Overall assessment

The core is in good shape: `swift test` passes 247 tests with one environment-dependent skip, and the project builds successfully. The strongest work is the fixture-driven parsing, deterministic serialization, IOKit fallback, and honest handling of unknown USB facts.

The main risks are at the product boundary:

- App Store sandbox and distribution are not release-ready.
- Snapshot collection has concurrency and stale-data risks.
- Several failures are silently converted into empty or partial results.
- The Mac UI is functional but not yet deeply native, accessible, or scalable.
- Security findings are useful heuristics but can be misread as authoritative.
- There is no true GUI/UI automation or broad hardware-matrix validation.

## 1. Product and user value

1. Define the primary audience explicitly: troubleshooting users, developers, IT administrators, or security-conscious users.
2. Make the first screen answer what is connected, where it is connected, and at what negotiated speed.
3. Add explanations for USB mode, cable capability, PD contract, and restricted status.
4. Add guided troubleshooting flows for slow USB, charge-only, missing devices, and unexpected restrictions.
5. Visually distinguish observed facts, inferred conclusions, and unavailable data.
6. Add a clear last-successful-read state separate from loading.
7. Add a machine-readable diagnostic bundle for support requests.
8. Publish a compatibility matrix for macOS versions and Apple Silicon/Intel.
9. Explain permissions, subprocesses, notifications, and local-only data on first run.
10. Define product metrics such as time to identify a port or speed bottleneck.

## 2. Information architecture and workflow

1. Replace the nine-item segmented picker with a sidebar or compact primary navigation.
2. Group views into Overview, Connections, Power, Security, History, and Diagnostics.
3. Make Overview the default landing page and keep specialist views secondary.
4. Add a persistent current-machine, current-read, and warning-count header.
5. Link security findings directly to affected devices or ports.
6. Link timeline entries to current or last-known device details.
7. Add a dedicated Warnings/Data Quality view.
8. Make baseline comparison a first-class workflow with Save, Load, and Compare actions.
9. Preserve sorting, filtering, grouping, and column visibility independently per view.
10. Add a command/search palette for opening views and actions.

## 3. macOS UX and visual design

1. Add explicit window restoration for size, position, and selected view.
2. Set a sensible default window size and minimum size for the widest tables.
3. Use a sidebar instead of the nine-segment toolbar control.
4. Make the toolbar customizable and expose actions through standard menus.
5. Add context menus to device, port, cable, finding, event, and storage rows.
6. Show refresh timestamp and source-health status prominently.
7. Replace long inline notes with concise summaries plus expandable details.
8. Improve empty states with explanations and actions such as Refresh or Connect a device.
9. Add confirmation before `diskutil eject`; the current action is immediate.
10. Make Security more scannable with severity grouping and affected-object links.

## 4. USB data correctness and model quality

1. Add captures for Apple Silicon, Intel, hubs, docks, USB4 hubs, Thunderbolt devices, storage, HID, displays, and charge-only cables.
2. Validate against multiple macOS releases, not only one registry shape.
3. Document source precedence when `system_profiler`, IOPort, IOUSB, and interface data disagree.
4. Detect duplicate devices when `locationID` is missing or reused.
5. Improve identity fallback beyond device name.
6. Preserve provenance per field, not only per device.
7. Separate negotiated speed, advertised capability, and theoretical maximum.
8. Distinguish not present, not reported, not readable, and not applicable.
9. Add schema migration tests for old exported snapshots.
10. Add fixtures for malformed, truncated, localized, and unexpected system-tool output.

## 5. Reliability and concurrency

1. Store and cancel the active refresh task.
2. Associate progress updates with a refresh generation to reject stale updates.
3. Serialize watcher and manual refreshes through one snapshot coordinator.
4. Prevent an older refresh from overwriting a newer hotplug snapshot.
5. Reconcile selection after refresh when selected row IDs disappear.
6. Clear `detailRowKey` when its row no longer exists.
7. Stop watchers, timers, pending tasks, and event-log work deterministically on shutdown.
8. Add timeouts around every subprocess.
9. Drain stdout and stderr safely; `Shell.run` pipes stderr but never reads it.
10. Stress-test rapid attach/detach, auto-refresh, and simultaneous manual refresh.

## 6. Error handling and observability

1. Do not represent storage-tool failures as indistinguishable empty storage.
2. Show which source failed and what data may be incomplete.
3. Replace export `try?` calls with visible errors and retry actions.
4. Add structured error codes for UI, CLI, and support bundles.
5. Record collection duration per source.
6. Add source-health states: healthy, unavailable, stale, partial, unsupported.
7. Show whether monitoring is IOKit-driven or polling-driven.
8. Add Copy Diagnostics with versions, failures, and timings.
9. Log unexpected parser shapes in a bounded privacy-safe log.
10. Test that every failure path is visible to the user.

## 7. Security and privacy

1. Label Security clearly as heuristic analysis, not malware detection.
2. Explain why mass storage is warning-level and allow configurable severity.
3. Link findings to the exact observed fields that caused them.
4. Avoid implying that a missing serial proves maliciousness.
5. Review privacy exposure of serials, location IDs, host names, and reports.
6. Warn that exports may contain sensitive hardware identifiers.
7. Add optional redaction for serials, host name, location IDs, and IDs.
8. Require confirmation before ejecting storage.
9. Make notification content configurable for sensitive device names.
10. Verify sandbox behavior before claiming Data Not Collected.

## 8. Performance and resource usage

1. Cache stable hardware metadata separately from changing connection state.
2. Avoid full `system_profiler` collection for every hotplug event where possible.
3. Coalesce manual, timer, and watcher refresh requests.
4. Display per-source timing so slow sources are explainable.
5. Rotate `events.jsonl`; the current append-only log can grow indefinitely.
6. Bound or stream large subprocess output.
7. Avoid repeatedly recomputing presentation rows during SwiftUI body evaluation.
8. Add performance tests for large hubs and event histories.
9. Add a low-power monitoring mode.
10. Reduce background activity when only the menu-bar extra remains.

## 9. Accessibility and internationalization

1. Add accessibility labels and values to status indicators, severity badges, toolbar icons, and charts.
2. Do not rely on color alone for state or severity.
3. Add text equivalents for the timeline sparkline and USB4 topology.
4. Verify full keyboard navigation through tables, lists, menus, sheets, and storage actions.
5. Add proper default and cancel buttons to every dialog.
6. Ensure Escape closes sheets, popovers, and transient UI consistently.
7. Localize all visible strings; several remain hardcoded, including Table, Copy, Export, Done, and detail empty-state text.
8. Localize report HTML metadata and generated report text where appropriate.
9. Test accessibility font sizes and window resizing.
10. Test VoiceOver with tables, findings, grouped lists, and details.

## 10. Distribution, sandbox, and release engineering

1. Wire `assets/entitlements/usbscope.entitlements` into the signing script.
2. Stop treating ad-hoc signing as a release artifact.
3. Add Developer ID signing and notarization for direct distribution.
4. Build a real App Store package path if Mac App Store distribution is intended.
5. Verify the sandboxed app with an Apple-issued signature and provisioning profile.
6. Replace remaining `system_profiler` subprocess dependencies if sandbox access fails.
7. Add CI checks for entitlements, bundle ID, architecture, minimum macOS, and signatures.
8. Add Gatekeeper and notarization validation to release automation.
9. Make `CFBundleVersion` a monotonically increasing build number.
10. Add an installed-bundle smoke test covering launch, hardware reads, exports, and notifications.

The current build script creates an ad-hoc signed app and does not consume the entitlements file. The Mac App Store path is therefore incomplete even though some metadata and documentation already exist.

## 11. Testing and quality assurance

1. Add real UI tests instead of relying mainly on presentation-layer unit tests.
2. Add snapshots for all views in light, dark, reduced-motion, and accessibility-size modes.
3. Add keyboard-only UI tests.
4. Add accessibility-tree tests.
5. Add subprocess timeout and stderr-flood tests.
6. Add concurrency tests for overlapping refreshes and watcher events.
7. Add tests for export failures, full disks, denied file access, and cancelled panels.
8. Add a hardware capture matrix across macOS versions and device classes.
9. Add fuzz tests for plist and JSON parser inputs.
10. Replace the skipped power-source test with a deterministic fixture-backed CI test.

## 12. Maintainability and API design

1. Introduce a `SnapshotCoordinator` instead of keeping orchestration in `AppState`.
2. Separate UI state from hardware collection state.
3. Use `ReportFormat` everywhere instead of stringly typed export formats.
4. Centralize all visible strings and remove hardcoded English.
5. Centralize subprocess timeout, stderr, cancellation, and diagnostics policy.
6. Add protocols for every OS adapter so failures are injectable consistently.
7. Version the serialized snapshot schema explicitly.
8. Document source precedence and merge rules beside the model.
9. Reduce duplicated CLI/app presentation logic while retaining shared semantics.
10. Add architecture checks preventing UI targets from owning low-level collection concerns.

## Recommended implementation order

### P0 — release and correctness blockers

1. Fix App Store sandbox, signing, and distribution.
2. Serialize and cancel refresh/watch tasks.
3. Add subprocess timeouts and safe stderr handling.
4. Add visible source-failure states.
5. Add eject confirmation.
6. Add real UI and accessibility validation.

### P1 — major product improvements

1. Replace the nine-way segmented picker with a sidebar.
2. Add provenance and data-quality indicators.
3. Improve baseline and diagnostic workflows.
4. Add hardware capture coverage.
5. Rotate event logs and optimize refresh collection.
6. Add redacted diagnostic/report export.

### P2 — polish

1. Complete localization.
2. Improve visual hierarchy and empty states.
3. Add toolbar customization and context menus.
4. Add a command palette.
5. Expand report customization and configurable security severity.
