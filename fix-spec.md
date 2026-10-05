# usbscope Fix Specification

This document turns the findings in [analysis.md](analysis.md) into implementation-ready work items. Each item is intentionally scoped so it can later become an issue, phase, or pull request.

Priority:

- **P0** — release, safety, correctness, or data-integrity blocker.
- **P1** — major usability, reliability, or product improvement.
- **P2** — polish, scale, or long-term maintainability.

Common definition of done: implementation, unit tests, relevant integration/UI tests, updated documentation, and a verified release/build path where applicable.

## 1. Product and user value

### 1.1 Define the primary audience — P1

**Spec:** Document primary personas and their top tasks. At minimum cover troubleshooting users, developers, IT administrators, and security-conscious users. Map each persona to the views and actions they need.

**Acceptance:** A product brief exists; every top-level view has a stated user job; the default landing experience is justified against those jobs.

### 1.2 Make the first screen diagnostic — P1

**Spec:** Redesign Overview around connected ports and devices. Show port, attached device, negotiated mode, active transports, power status, and a concise problem indicator before secondary metadata.

**Acceptance:** A user can identify the connected device, physical port, negotiated speed, and charge/data state without opening another view or detail sheet.

### 1.3 Explain technical fields — P1

**Spec:** Add contextual help for USB mode, cable capability, PD contract, transport, restriction, and liquid-detection fields. Explain advertised capability versus negotiated state.

**Acceptance:** Each technical field has a short plain-language explanation and a link or expandable “how this is determined” note where ambiguity exists.

### 1.4 Add guided troubleshooting — P1

**Spec:** Add four guided diagnostics: slow connection, charge-only connection, device missing, and restricted device. Each flow evaluates observed facts, lists likely causes, and provides next actions without claiming certainty.

**Acceptance:** Each flow handles success, unknown data, and conflicting data; every recommendation identifies the evidence behind it.

### 1.5 Classify fact certainty — P1

**Spec:** Extend presentation data with `observed`, `derived`, `unavailable`, and `stale` states. Use labels and icons in details and reports; do not rely on color alone.

**Acceptance:** A user can distinguish a macOS-reported fact from an inferred heuristic and from unavailable data in every major view.

### 1.6 Show last successful read — P1

**Spec:** Track `lastSuccessfulSnapshot`, `lastAttemptAt`, `lastFailureAt`, and `dataFreshness`. During a failed refresh, retain the last valid snapshot but clearly mark it stale.

**Acceptance:** A failed refresh never looks like current data; the UI shows when the displayed snapshot was captured and why it is stale.

### 1.7 Diagnostic bundle — P1

**Spec:** Add “Export Diagnostics” producing a ZIP or directory containing redacted snapshot JSON, source warnings, timing data, app/version metadata, and recent event history.

**Acceptance:** Export is atomic, reports errors, supports redaction, and never includes raw credentials or unrelated user files.

### 1.8 Compatibility matrix — P1

**Spec:** Maintain a support matrix covering minimum macOS, current macOS, Intel, Apple Silicon, sandboxed bundle, direct bundle, and CLI execution. Record source availability and known limitations.

**Acceptance:** README and release notes state tested configurations and known unsupported fields.

### 1.9 First-run explanation — P1

**Spec:** Add a first-run sheet explaining local-only collection, system sources, notification permission, sandbox limitations, and export privacy.

**Acceptance:** The sheet is dismissible, not shown repeatedly, localized, and accessible by keyboard and VoiceOver.

### 1.10 Product metrics — P2

**Spec:** Define non-invasive local QA metrics only: time-to-first-snapshot, source latency, failed-source rate, and time-to-identify-device. Do not add telemetry without an explicit privacy decision.

**Acceptance:** Metrics are available in local diagnostics and are not sent over the network.

## 2. Information architecture and workflow

### 2.1 Replace the nine-way segmented picker — P1

**Spec:** Use a collapsible `NavigationSplitView` sidebar with sections for Overview, Connections, Power, Security, History, and Diagnostics. Keep keyboard shortcuts for the first nine commands if useful.

**Acceptance:** All views remain reachable within one click, the sidebar collapses, and the selected section persists across launches.

### 2.2 Group views — P1

**Spec:** Define a stable navigation enum with user-facing groups: Overview; Ports, Cables, Devices; Power; Security; Timeline; USB4; Diff.

**Acceptance:** Group labels are localized, appear in the sidebar and menu bar, and do not change based on available hardware.

### 2.3 Improve Overview landing — P1

**Spec:** Launch into Overview unless the user has explicitly chosen another default. Overview must include a clear “no devices,” “loading,” and “partial data” state.

**Acceptance:** First launch is useful with no connected devices and with source failures.

### 2.4 Persistent status header — P1

**Spec:** Add a compact header showing host, OS, read time, connected ports, devices, warning count, and freshness. Make it available to reports and accessibility APIs.

**Acceptance:** Header updates atomically with snapshots and does not display mixed values from different reads.

### 2.5 Finding-to-object navigation — P1

**Spec:** Use `Finding.port`, `Finding.device`, and `locationID` to add an Open button or double-click action. Resolve to the matching view and select the row.

**Acceptance:** Every finding with an identity opens its source row; unresolved identities show an explanation instead of failing silently.

### 2.6 Event-to-device navigation — P2

**Spec:** Store enough identity in events to resolve current devices. Add context action “Show device” and show last-known details for detached devices.

**Acceptance:** Attached events open current details; detached events open an immutable historical detail view.

### 2.7 Warnings/data-quality view — P1

**Spec:** Add a view listing warnings by source, severity, timestamp, affected fields, and remediation. Include a “copy technical details” action.

**Acceptance:** Partial collection is understandable without reading logs or the footer.

### 2.8 Baseline workflow — P1

**Spec:** Add Save Baseline, Load Baseline, Rename Baseline, Clear Baseline, and Compare actions. Store metadata with the baseline: creation time, host, app version, OS version.

**Acceptance:** Users can create and compare a baseline entirely in the GUI; incompatible schema versions are rejected with a useful message.

### 2.9 Per-view preferences — P2

**Spec:** Persist sort order, filters, grouping, column visibility, and selection policy per view. Do not reuse invalid grouping fields across views.

**Acceptance:** Switching views and relaunching preserves each view’s configuration independently.

### 2.10 Command palette — P2

**Spec:** Add a searchable command palette listing navigation, refresh, export, baseline, copy, and monitoring commands with shortcuts and enabled state.

**Acceptance:** Every visible primary action is discoverable by keyboard through the palette.

## 3. macOS UX and visual design

### 3.1 Window restoration — P1

**Spec:** Assign a stable autosave name to the main window and persist selected view/sidebar state using scene restoration or explicit preferences.

**Acceptance:** Relaunch restores size, position, fullscreen/split state where supported, sidebar visibility, and selected view.

### 3.2 Window sizing — P1

**Spec:** Set a default size optimized for the Overview and a minimum size that preserves usable table columns. Allow free resizing and fullscreen.

**Acceptance:** The first launch is neither cramped nor oversized; no primary control disappears at the minimum size.

### 3.3 Native sidebar — P1

**Spec:** Implement `NavigationSplitView` with source-list styling, selection state, collapse control, and persistent width.

**Acceptance:** Sidebar works with mouse, keyboard, VoiceOver, fullscreen, and narrow window widths.

### 3.4 Customizable toolbar — P2

**Spec:** Assign stable toolbar item IDs and expose refresh, filter, baseline, copy, export, details, and monitoring actions through a customizable toolbar.

**Acceptance:** Toolbar items can be rearranged or hidden without removing menu commands.

### 3.5 Context menus — P1

**Spec:** Add context menus for rows. Include Show Details, Copy Row, Copy Identifier, Compare, Export, and device-specific actions. Storage rows additionally include Eject.

**Acceptance:** Context actions operate on the clicked row, not merely the current selection; destructive actions confirm.

### 3.6 Source-health status — P1

**Spec:** Add a source status control showing healthy/partial/failed/stale and a popover listing source names, duration, warning, and last success.

**Acceptance:** Users can explain incomplete data without inspecting logs.

### 3.7 Concise notes — P1

**Spec:** Limit table cells to a short summary. Move long power/cable/liquid details into the detail sheet or an expandable inspector.

**Acceptance:** Tables remain readable at the default window width and preserve full information in details/export.

### 3.8 Actionable empty states — P1

**Spec:** Define empty states per view. Include reason, current source status, and a primary action such as Refresh, Load Baseline, or Connect a device.

**Acceptance:** Empty states never imply failure when no matching hardware is normal.

### 3.9 Eject confirmation — P0

**Spec:** Present a confirmation dialog containing disk identifier, volume name, mount point, and warning that mounted volumes may be unmounted. Provide Cancel as the default-safe action.

**Acceptance:** Eject cannot occur from a single accidental click; Escape cancels; failures remain visible.

### 3.10 Security visual hierarchy — P1

**Spec:** Group findings by severity, show counts, show affected object, and provide evidence/detail disclosure. Use icons and text in addition to color.

**Acceptance:** Warning, attention, and informational findings are distinguishable in light mode, dark mode, grayscale, and VoiceOver.

## 4. USB data correctness and model quality

### 4.1 Hardware capture matrix — P1

**Spec:** Create a versioned capture catalog for Apple Silicon, Intel, hubs, docks, USB4 hubs, Thunderbolt devices, storage, HID, displays, and charge-only connections.

**Acceptance:** Every supported capture has parser tests, expected normalized model values, and documented hardware provenance.

### 4.2 macOS-version validation — P1

**Spec:** Run the capture suite against supported macOS releases and record field differences. Treat unknown fields as non-fatal.

**Acceptance:** CI or scheduled validation identifies parser regressions caused by OS output changes.

### 4.3 Source precedence — P1

**Spec:** Define a precedence table for every merged field and document conflict behavior. Preserve both raw candidates in diagnostics when values disagree.

**Acceptance:** A conflict is deterministic, test-covered, and visible as a data-quality warning where material.

### 4.4 Duplicate identity detection — P1

**Spec:** Detect duplicate `locationID`, duplicate fallback identity, and contradictory device records. Mark ambiguous records instead of silently overwriting dictionary entries.

**Acceptance:** No source record disappears without a warning explaining the collision.

### 4.5 Stronger identity fallback — P1

**Spec:** Implement a documented identity hierarchy: location ID, VID/PID plus serial, stable registry ID, bus/port path, then generated read-local identity. Mark weak identities.

**Acceptance:** Diff and events do not incorrectly treat two same-named devices as one without a warning.

### 4.6 Field provenance — P1

**Spec:** Add provenance metadata at field or logical-group level, such as `systemProfiler`, `ioPort`, `ioUSB`, `interfaceRegistry`, and `diskutil`.

**Acceptance:** Detail and diagnostics can answer where each important fact came from.

### 4.7 Capability versus negotiated speed — P1

**Spec:** Model `advertisedModes`, `negotiatedMode`, `activeTransports`, and `maximumObservedRate` separately. Update labels and reports to avoid conflating them.

**Acceptance:** A USB4-capable port connected at USB 2 is represented as capable of USB4 but currently negotiated at USB 2.

### 4.8 Data-state semantics — P1

**Spec:** Replace ambiguous nil rendering with a typed availability state: absent, unknown, unavailable, unsupported, stale, or present.

**Acceptance:** UI, JSON, CSV, and reports preserve the distinction where it matters.

### 4.9 Snapshot migrations — P1

**Spec:** Add explicit schema versioning and migration handlers for older JSON documents. Preserve backward-compatible loading where practical.

**Acceptance:** Old fixtures load or fail with a migration message; current output declares its schema version.

### 4.10 Malformed-output fixtures — P1

**Spec:** Add parser fixtures for invalid plist, invalid JSON, missing keys, wrong types, partial output, localized strings, and unexpected nesting.

**Acceptance:** Parsers never crash and warnings identify the affected source and field.

## 5. Reliability and concurrency

### 5.1 Refresh task ownership — P0

**Spec:** Add a cancellable refresh task property in `AppState`. Cancel it on replacement, shutdown, and explicit stop. Use a task result carrying generation ID and snapshot.

**Acceptance:** Only the current generation may mutate `snapshot`, `storage`, `progress`, `errorMessage`, or status.

### 5.2 Progress generations — P0

**Spec:** Tag progress callbacks with refresh generation. Ignore callbacks whose generation is not current.

**Acceptance:** Progress never jumps backward or remains visible after a newer refresh completes.

### 5.3 Snapshot coordinator — P0

**Spec:** Introduce an actor or serial coordinator owning manual refresh, timer refresh, watcher updates, and initial load. It emits ordered snapshot events to `AppState`.

**Acceptance:** There is one authoritative ordering of snapshots and no concurrent collection mutates presentation state directly.

### 5.4 Stale overwrite prevention — P0

**Spec:** Attach monotonic sequence numbers and capture timestamps to every collection. Reject results older than the currently applied result.

**Acceptance:** A slower earlier refresh cannot replace a newer hotplug or manual refresh.

### 5.5 Selection reconciliation — P1

**Spec:** After applying a snapshot or filter, intersect selection with visible row IDs and preserve only valid selection.

**Acceptance:** Copy, details, and context menus never target removed or invisible rows unexpectedly.

### 5.6 Detail reconciliation — P1

**Spec:** Validate `detailRowKey` after every snapshot/view change. Close or replace the inspector when its subject disappears.

**Acceptance:** The detail sheet never displays an empty or mismatched object after refresh.

### 5.7 Deterministic shutdown — P0

**Spec:** Add an application termination hook that stops watcher, timer, active tasks, pending debounces, and log writes. Make stop idempotent.

**Acceptance:** No background callback mutates released state during termination; repeated stop calls are safe.

### 5.8 Subprocess timeouts — P0

**Spec:** Extend `Shell.run` with timeout and cancellation support. Terminate, reap, and report timed-out processes with command identity.

**Acceptance:** A hung system tool cannot hang refresh, export, or eject indefinitely.

### 5.9 Safe pipe draining — P0

**Spec:** Read stdout and stderr concurrently or merge stderr into a bounded diagnostic stream. Enforce output-size limits.

**Acceptance:** A child emitting large stderr cannot deadlock the parent, and diagnostics remain bounded.

### 5.10 Concurrency stress tests — P1

**Spec:** Add deterministic tests for overlapping refresh, attach/detach bursts, auto-refresh, watcher stop during collection, and cancellation.

**Acceptance:** Tests prove ordering, cancellation, and final-state correctness under repeated runs.

## 6. Error handling and observability

### 6.1 Storage failure state — P0

**Spec:** Change `StorageSource.inventory()` to return an explicit result with devices, warnings, and source status. Render “no storage” differently from “diskutil unavailable.”

**Acceptance:** Users can distinguish empty inventory from collection failure.

### 6.2 Partial-source explanation — P1

**Spec:** Add source-specific warnings to the status header, warnings view, reports, and diagnostics. State which fields are affected.

**Acceptance:** Every partial snapshot explains its missing data.

### 6.3 Export error handling — P0

**Spec:** Replace silent `try?` writes with atomic temporary-file writes, error presentation, retry, and cancellation handling. Use format-specific extensions.

**Acceptance:** A failed export always produces a visible actionable error and never leaves a partial target file.

### 6.4 Structured errors — P1

**Spec:** Define an `AppErrorCode`/`SourceError` model with source, operation, severity, user message, technical message, and recovery action.

**Acceptance:** UI, CLI, diagnostics, and tests use stable error categories rather than parsing strings.

### 6.5 Per-source timing — P1

**Spec:** Capture start/end/duration and result for each SnapshotStage and subprocess. Add timing to diagnostics and optional debug UI.

**Acceptance:** Slow reads can be identified without profiling the app externally.

### 6.6 Source-health model — P1

**Spec:** Add `healthy`, `partial`, `failed`, `stale`, `unsupported`, and `notApplicable` states. Define transition rules per refresh.

**Acceptance:** The UI never reports an empty normal state when a source actually failed.

### 6.7 Monitoring mode indicator — P1

**Spec:** Display IOKit event-driven, polling fallback, or disabled status, including polling interval and last event.

**Acceptance:** Users know whether device changes are detected immediately or on a delay.

### 6.8 Copy Diagnostics — P1

**Spec:** Add a clipboard action containing app version, OS, architecture, source statuses, timings, warnings, and schema version, with identifiers redacted by default.

**Acceptance:** Support can request one pasteable diagnostic payload without exposing raw device serials by default.

### 6.9 Bounded parser log — P2

**Spec:** Add a rotating local log for unexpected source shapes. Store event type and field path, not full raw payload by default.

**Acceptance:** Logs are size-bounded, privacy-aware, and useful for adding regression fixtures.

### 6.10 Failure-path coverage — P1

**Spec:** Create a failure matrix covering every adapter and UI action. Each row must specify user-visible state, technical diagnostic, and recovery.

**Acceptance:** CI tests every material failure row.

## 7. Security and privacy

### 7.1 Heuristic labeling — P0

**Spec:** Rename or subtitle Security as “Security observations” or “Heuristic security posture.” Add a persistent explanation that the app is not malware detection.

**Acceptance:** No screen or report describes heuristic output as a verdict.

### 7.2 Configurable severity — P2

**Spec:** Define default severity rules and user overrides. Preserve stable rule IDs in exports while allowing display severity customization.

**Acceptance:** Users can lower or raise presentation severity without changing raw observations.

### 7.3 Evidence links — P1

**Spec:** Add structured evidence to each `Finding`: field path, observed value, source, and evaluation rule. Show it in an expandable detail view.

**Acceptance:** Every finding can be traced to concrete snapshot data.

### 7.4 Missing serial wording — P1

**Spec:** Change wording from implication to observation: “No serial was reported by macOS; device identity may be less stable across reads.”

**Acceptance:** Tests pin the non-alarmist wording in UI and reports.

### 7.5 Privacy inventory — P0

**Spec:** Inventory every field exported, logged, notified, or persisted. Classify host identity, serial, location ID, VID/PID, mount path, and event history.

**Acceptance:** Privacy documentation matches actual behavior and export formats.

### 7.6 Export privacy warning — P1

**Spec:** Add a pre-export disclosure for reports and diagnostics explaining that hardware identifiers may be included, with a redaction option.

**Acceptance:** The warning is shown once per format/version, localizable, and accessible.

### 7.7 Redaction — P1

**Spec:** Add a `RedactionPolicy` covering serials, host, location IDs, paths, and event identities. Apply it consistently to JSON, CSV, Markdown, HTML, clipboard, and diagnostics.

**Acceptance:** Redacted output contains no original values and clearly indicates redaction.

### 7.8 Eject authorization — P0

**Spec:** Confirm target identity and require a deliberate confirmation before invoking `diskutil eject`. Handle authorization and command failure distinctly.

**Acceptance:** No destructive storage action is executed without an explicit confirmation.

### 7.9 Notification privacy — P1

**Spec:** Add notification detail levels: full device name, generic device event, or disabled. Avoid serials and sensitive paths in notifications.

**Acceptance:** Preferences control notification content and tests verify redaction.

### 7.10 Sandbox privacy claims — P0

**Spec:** Verify actual sandboxed behavior with Apple-issued signing. Update App Store privacy answers and documentation only after validating all data paths.

**Acceptance:** A signed sandbox build successfully reads supported data or clearly reports unsupported sources.

## 8. Performance and resource usage

### 8.1 Stable metadata cache — P1

**Spec:** Cache model/chip/host and stable descriptor data with invalidation rules. Refresh dynamic connection, power, and restriction state more frequently.

**Acceptance:** Auto-refresh reduces expensive stable-source reads without showing stale dynamic state.

### 8.2 Hotplug collection strategy — P1

**Spec:** On hotplug, collect only changed sources where safe, or debounce and share a single full collection with manual refresh.

**Acceptance:** A device burst produces bounded collection work and one coherent UI update.

### 8.3 Refresh coalescing — P0

**Spec:** Coordinator accepts refresh requests as intents and coalesces them while one read is active. Preserve the strongest reason, such as user-requested refresh.

**Acceptance:** Repeated timer and event requests do not launch concurrent full collections.

### 8.4 Timing visibility — P1

**Spec:** Show total read duration and top slow sources in diagnostics; optionally show a compact status tooltip.

**Acceptance:** Users can understand a slow refresh without guessing.

### 8.5 Event-log rotation — P1

**Spec:** Rotate by size and age, retain a configurable number of files, and recover from malformed or partially written final lines.

**Acceptance:** Event history has a documented maximum disk footprint.

### 8.6 Output bounds — P0

**Spec:** Add maximum stdout/stderr bytes, timeout, and truncation markers to `Shell.run`. Make limits configurable for tests.

**Acceptance:** Malicious or unexpectedly large tool output cannot exhaust memory.

### 8.7 Presentation memoization — P2

**Spec:** Compute rows once per snapshot/view/filter/grouping state and cache by immutable input identity.

**Acceptance:** Instruments or signposts show no repeated full row transformation during ordinary scrolling.

### 8.8 Large-data performance tests — P1

**Spec:** Generate fixtures for large hubs, many interfaces, 500 events, and large reports. Set time and memory budgets.

**Acceptance:** CI catches regressions beyond agreed thresholds.

### 8.9 Low-power monitoring — P2

**Spec:** Add a monitoring profile with configurable interval, reduced source collection, and automatic suspension on battery if desired.

**Acceptance:** The user can see exactly which data is reduced and can disable the profile.

### 8.10 Menu-bar-only behavior — P1

**Spec:** When the main window closes, keep only required monitoring work. Stop expensive timers and full history work when monitoring is disabled.

**Acceptance:** Activity Monitor and timing diagnostics demonstrate bounded background work with no open window.

## 9. Accessibility and internationalization

### 9.1 Accessibility semantics — P0

**Spec:** Add labels, values, hints, and traits for status indicators, severity badges, toolbar icons, charts, and topology rows.

**Acceptance:** VoiceOver can identify the object, state, action, and result without relying on visual color.

### 9.2 Color-independent states — P0

**Spec:** Pair every color state with text, icon, or shape. Ensure contrast meets WCAG 2.2 AA where applicable.

**Acceptance:** State remains understandable in grayscale and with common color-vision deficiencies.

### 9.3 Chart alternatives — P1

**Spec:** Add an accessible table or summary for timeline values and a hierarchical text representation for USB4 topology.

**Acceptance:** All chart/topology information is available without visual inspection.

### 9.4 Keyboard navigation — P0

**Spec:** Test and implement Tab, Shift-Tab, arrow navigation, Return, Escape, Delete where applicable, and all menu shortcuts.

**Acceptance:** The main workflows can be completed without a pointing device.

### 9.5 Dialog defaults — P0

**Spec:** Mark safe primary and cancel actions using default/cancel keyboard shortcuts. Ensure destructive confirmation defaults to Cancel.

**Acceptance:** Return and Escape behave consistently in every sheet and dialog.

### 9.6 Escape behavior — P1

**Spec:** Add explicit cancellation for custom sheets, popovers, save panels, filters, and in-progress operations.

**Acceptance:** Escape closes or cancels the active transient operation without changing committed data.

### 9.7 Complete localization — P1

**Spec:** Move all visible strings into `Strings.swift` or a localized resource, including menu names, buttons, detail empty states, tooltip text, and report labels.

**Acceptance:** A scan finds no user-visible hardcoded strings outside localization resources.

### 9.8 Localized reports — P2

**Spec:** Parameterize report language and HTML `lang` metadata. Keep schema keys and stable rule IDs language-neutral.

**Acceptance:** Reports can be generated in each supported language without changing machine-readable identifiers.

### 9.9 Accessibility sizes — P1

**Spec:** Test larger system fonts, increased contrast, reduced transparency, and reduced motion. Replace fixed widths where content clips.

**Acceptance:** Core workflows remain usable at accessibility text sizes.

### 9.10 VoiceOver test plan — P0

**Spec:** Create scripted VoiceOver scenarios for navigation, refresh, table selection, finding inspection, baseline comparison, export, and eject confirmation.

**Acceptance:** Scenarios pass on a signed app build and regressions are documented.

## 10. Distribution, sandbox, and release engineering

### 10.1 Consume entitlements — P0

**Spec:** Update the bundle build script to sign with `assets/entitlements/usbscope.entitlements` in the appropriate distribution mode. Verify embedded entitlements.

**Acceptance:** CI fails if the intended entitlement is absent or unexpected entitlements are present.

### 10.2 Separate release signing modes — P0

**Spec:** Define explicit debug, ad-hoc test, Developer ID, and Mac App Store signing modes. Never label ad-hoc output as release-ready.

**Acceptance:** Artifact names and metadata identify signing mode; release mode requires the correct certificate.

### 10.3 Developer ID notarization — P0

**Spec:** Add archive, sign, notarize, staple, Gatekeeper assess, and checksum steps for direct distribution.

**Acceptance:** A clean Mac can open the distributed DMG without a developer exception.

### 10.4 Mac App Store package — P0

**Spec:** Add provisioning-profile embedding, Apple Distribution signing, installer package signing, validation, and App Store Connect upload documentation or automation.

**Acceptance:** A test archive passes local package/signature validation before upload.

### 10.5 Sandboxed data-path validation — P0

**Spec:** Build and run a real sandboxed bundle with an Apple-issued signature. Validate IOKit, system tools, diskutil, notifications, persistence, and exports.

**Acceptance:** Each source is marked verified, unsupported, or replaced by an in-process implementation.

### 10.6 Remove sandbox-incompatible subprocesses — P0

**Spec:** Replace blocked `system_profiler`, `ioreg`, or `diskutil` reads with in-process APIs where practical, or degrade with explicit source status.

**Acceptance:** The App Store build never silently loses primary functionality.

### 10.7 CI artifact validation — P0

**Spec:** Add checks for bundle ID, version, architecture, minimum OS, Info.plist, entitlements, signature, nested code, and executable launch.

**Acceptance:** Invalid artifacts fail before packaging or publication.

### 10.8 Notarization validation — P0

**Spec:** Add `spctl`, signature, stapler, and clean-machine launch validation to release CI.

**Acceptance:** The exact artifact users receive passes Gatekeeper validation.

### 10.9 Build-number policy — P1

**Spec:** Separate marketing version from monotonically increasing `CFBundleVersion`. Define release automation and collision checks.

**Acceptance:** Two submitted builds can never share a build number.

### 10.10 Installed-bundle smoke test — P0

**Spec:** Install the final artifact in a clean environment and verify launch, first read, hotplug monitoring, exports, notifications, and shutdown.

**Acceptance:** Smoke tests run against the signed artifact, not only the SwiftPM executable.

## 11. Testing and quality assurance

### 11.1 UI automation — P0

**Spec:** Add XCUITest or equivalent coverage for launch, navigation, refresh, filtering, details, baseline, export, security, and eject confirmation.

**Acceptance:** Critical GUI workflows run in CI or a documented release test job.

### 11.2 Visual snapshots — P1

**Spec:** Capture every view in light/dark appearance, empty/loaded/partial states, and accessibility sizes. Compare with reviewed baselines.

**Acceptance:** Visual regressions are detected without requiring manual inspection of every build.

### 11.3 Keyboard-only tests — P0

**Spec:** Automate or script keyboard workflows for navigation, selection, copy, details, export, refresh, baseline, and cancellation.

**Acceptance:** All primary workflows have documented keyboard paths.

### 11.4 Accessibility-tree tests — P0

**Spec:** Assert accessibility labels, traits, roles, values, and enabled states for important controls and rows.

**Acceptance:** Accessibility regressions fail tests or the release checklist.

### 11.5 Subprocess robustness tests — P0

**Spec:** Inject runners that hang, emit large stderr, emit malformed output, exit nonzero, or exceed output limits.

**Acceptance:** The app returns bounded, actionable errors in every case.

### 11.6 Concurrency tests — P0

**Spec:** Test generation ordering, cancellation, stale results, watcher events during refresh, and shutdown during collection.

**Acceptance:** Final state is deterministic across repeated runs.

### 11.7 File/export tests — P1

**Spec:** Test read-only destination, full-disk simulation, cancellation, overwrite, extension correction, atomicity, and redaction.

**Acceptance:** No export path silently loses data or leaves a misleading file.

### 11.8 Hardware matrix — P1

**Spec:** Maintain real captures plus manual test procedures for representative hardware. Record expected limitations.

**Acceptance:** Release notes identify tested devices and known failures.

### 11.9 Parser fuzzing — P1

**Spec:** Fuzz plist/JSON trees with missing keys, wrong types, deep nesting, oversized strings, duplicate identifiers, and unexpected arrays.

**Acceptance:** No crash, unbounded allocation, or silent data corruption within defined limits.

### 11.10 Deterministic power test — P1

**Spec:** Replace reliance on live power-source availability with fixture-backed tests, while retaining one optional live smoke test.

**Acceptance:** The normal suite has zero skipped functional coverage for power option ordering.

## 12. Maintainability and API design

### 12.1 SnapshotCoordinator — P0

**Spec:** Create an actor or serial service owning collection requests, generation IDs, cancellation, watcher integration, and result ordering. `AppState` becomes a consumer.

**Acceptance:** `AppState` no longer directly coordinates multiple independent snapshot producers.

### 12.2 Separate state layers — P1

**Spec:** Split hardware domain state, collection state, UI preferences, and transient UI state into separate types.

**Acceptance:** Hardware collection can be tested without SwiftUI and preferences can be tested without IOKit.

### 12.3 Typed export formats — P1

**Spec:** Replace `export(format: String)` with `export(format: ExportFormat)` and route JSON, CSV, Markdown, and HTML through typed dispatch.

**Acceptance:** Invalid formats are impossible at compile time and each format defines extension/content type.

### 12.4 String centralization — P1

**Spec:** Move all user-visible labels, errors, tooltips, report labels, and dialog text into localization resources or typed string keys.

**Acceptance:** Static checks identify hardcoded user-visible strings outside approved resources.

### 12.5 Subprocess service — P0

**Spec:** Define a `CommandExecutor` protocol with timeout, cancellation, environment, output limits, stderr capture, and structured result.

**Acceptance:** All OS command adapters use the same safe execution policy.

### 12.6 Adapter protocols — P1

**Spec:** Define protocols for profiler, IOKit reader, storage, charging, Thunderbolt, interfaces, and event log. Keep production implementations separate from fixture doubles.

**Acceptance:** Every adapter failure mode is injectable without launching a real system process.

### 12.7 Explicit schema version — P1

**Spec:** Add a required snapshot schema version and migration registry. Keep stable JSON keys separate from localized presentation strings.

**Acceptance:** Schema changes require a migration or an explicit compatibility decision.

### 12.8 Merge-rule documentation — P1

**Spec:** Document identity joins, source precedence, orphan handling, ordering, and unknown-value semantics next to implementation and in public docs.

**Acceptance:** A maintainer can explain why each merged field has its final value.

### 12.9 Shared presentation boundary — P2

**Spec:** Keep stable row models and formatting semantics shared between CLI and app, while allowing platform-specific layout and interaction.

**Acceptance:** CLI and GUI agree on facts and rule IDs without forcing terminal formatting into SwiftUI.

### 12.10 Architecture checks — P2

**Spec:** Add module boundaries and review checks preventing UI targets from importing low-level implementation details directly. Enforce through package dependencies and CI linting.

**Acceptance:** New collection code belongs in Core/adapters, not in views or `AppState`.

## Delivery sequence

### Phase A — safety and release blockers

1. Snapshot coordinator, cancellation, generation ordering, and subprocess safety.
2. Visible source failures and non-silent exports.
3. Eject confirmation and privacy/redaction policy.
4. Signed sandbox validation and release artifact checks.
5. UI/accessibility smoke tests for critical workflows.

### Phase B — workflow and product quality

1. Sidebar/navigation redesign.
2. Overview and data-quality redesign.
3. Baseline and diagnostics workflow.
4. Provenance and capability-versus-negotiated data model.
5. Hardware and macOS-version capture matrix.

### Phase C — scale and polish

1. Caching, refresh coalescing, event-log rotation, and low-power monitoring.
2. Complete localization and accessibility-size support.
3. Toolbar customization, command palette, context menus, and richer reports.
4. Parser fuzzing, performance budgets, and architecture enforcement.
