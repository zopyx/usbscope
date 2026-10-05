# Release validation matrix

Automated checks run on every change:

| Area | Command | Expected result |
| --- | --- | --- |
| Core and UI support | `swift test` | All tests pass; skips are explained |
| App build | `swift build -c debug --product usbscope-app` | Build succeeds |
| Bundle shape | `scripts/build-swift-app.sh --debug --no-archive --no-verify` | Bundle is signed and validated |
| Installed-bundle smoke | `scripts/smoke-swift-app.sh dist/usbscope-swift.app` | Exact bundle executable reports version, first-read rows, atomic JSON/CSV exports, a diagnostic bundle, watcher start/stop, all ten offscreen views, and signature |
| Fixture snapshot smoke | `scripts/snapshot-fixture-smoke.sh dist/usbscope-swift.app SwiftTests/Golden/snapshot.json` | All ten offscreen views render from a stable, checked-in input rather than live host/time data |
| Visual baseline comparison | `scripts/check-swift-visual-baselines.sh dist/usbscope-swift.app SwiftTests/Golden/snapshot.json docs/screenshots/fixture-baselines` | Exact fixture-driven PNG output matches the reviewed baseline for every view |
| Localization | `scripts/check-localization.sh` | No user-visible SwiftUI/AppKit literals bypass the string table |
| UI contract | `scripts/check-ui-contract.sh` | Keyboard commands, accessibility hooks, all ten view routes, and actionable empty/source-health controls remain wired |
| Large-data performance | `swift test --filter PerformanceTests` | 500-device report and 1,000-entry history stay within budgets |
| Parser robustness | `swift test --filter ParserFuzzTests` | Malformed and deeply nested source trees do not crash adapters |
| Concurrency and export safety | `swift test --filter FixSpecTests` | Refresh bursts are serialized, stderr remains bounded, and atomic exports leave no temporary files |
| Warnings/data quality | `swift test --filter PresentationTests` plus app smoke run | Warnings are navigable with source, severity, field, remediation, and redacted technical copy |
| Capability/negotiated model | `swift test --filter FixSpecTests` | Advertised modes, negotiated mode, and maximum observed rate remain distinct in JSON and details |
| Script safety | `bash -n scripts/*.sh` | No shell syntax errors |
| Patch hygiene | `git diff --check` | No whitespace errors |

Credentialed/manual release gates:

| Gate | Owner/evidence |
| --- | --- |
| Developer ID signing and notarization | Apple certificate/profile, `--notarize`, stapler and Gatekeeper output |
| App Store sandbox | Apple-issued application/installer signing, provisioning profile, and real hardware capture |
| Intel and current macOS coverage | CI or physical Intel Mac plus the current supported macOS release |
| VoiceOver | Follow `voiceover-test-plan.md` on the signed app |
| Large-data profiling | Instruments or a credentialed release job | Record memory and scrolling behavior on representative hardware |

The local ad-hoc build cannot prove Apple certificate, provisioning, App Store,
notarization, or hardware-specific behavior. Those gates remain explicitly
blocked until the corresponding Apple credentials or machines are available;
the build scripts fail closed when required signing inputs are missing.
