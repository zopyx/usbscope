# Release validation matrix

Automated checks run on every change:

| Area | Command | Expected result |
| --- | --- | --- |
| Core and UI support | `swift test` | All tests pass; skips are explained |
| App build | `swift build -c debug --product usbscope-app` | Build succeeds |
| Bundle shape | `scripts/build-swift-app.sh --debug --no-archive --no-verify` | Bundle is signed and validated |
| Script safety | `bash -n scripts/*.sh` | No shell syntax errors |
| Patch hygiene | `git diff --check` | No whitespace errors |

Credentialed/manual release gates:

| Gate | Owner/evidence |
| --- | --- |
| Developer ID signing and notarization | Apple certificate/profile, `--notarize`, stapler and Gatekeeper output |
| App Store sandbox | Apple-issued application/installer signing, provisioning profile, and real hardware capture |
| Intel and current macOS coverage | CI or physical Intel Mac plus the current supported macOS release |
| VoiceOver | Follow `voiceover-test-plan.md` on the signed app |
| Large-data performance | Run the large-fixture/performance suite and record time/memory budgets |

The local ad-hoc build cannot prove Apple certificate, provisioning, App Store,
notarization, or hardware-specific behavior. Those gates remain explicitly
blocked until the corresponding Apple credentials or machines are available;
the build scripts fail closed when required signing inputs are missing.
