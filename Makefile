# usbscope — developer tasks (Swift only)
#
# Every target is self documenting: `make` (or `make help`) lists them grouped by
# section, and the `##` comment next to a target is the description.
#
# The whole project is Swift: `swift build` + `swift test` are the only gates, and
# the toolchain is whatever Xcode/Swift 6 provides. There is no Python environment
# to sync and no virtualenv.

SHELL := /bin/bash
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

SWIFT ?= swift
CONFIG ?= debug
VERSION := $(shell sed -n 's/^let version = "\([^"]*\)".*/\1/p' Sources/usbscope/main.swift | head -1)

.PHONY: help doctor env build test check clean distclean version \
        swift swift-build swift-test swift-golden swift-run-app swift-app-check swift-app-bundle \
        swift-app-dmg swift-app-smoke swift-app-fixture-smoke \
        ui-contract run watch snapshot checksums man completions

## ---------------------------------------------------------------------------
## Setup & quality
## ---------------------------------------------------------------------------

help: ## show this help
	@printf '\nusbscope %s — make targets (Swift only)\n\n' "$(VERSION)"
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\n  variables: CONFIG=%s (debug|release), VERSION=%s\n\n' "$(CONFIG)" "$(VERSION)"

doctor: ## check the tools this repo needs (swift, codesign, plutil, hdiutil)
	@command -v $(SWIFT) >/dev/null && echo "swift      $$($(SWIFT) --version 2>/dev/null | grep -o 'Apple Swift version [^)]*)' | head -1)" || echo "swift      MISSING (install Xcode or the command line tools)"
	@command -v codesign >/dev/null && echo "codesign   ok (ad-hoc app signature)" || echo "codesign   missing"
	@command -v plutil >/dev/null && echo "plutil     ok (Info.plist validation)" || echo "plutil     missing"
	@command -v hdiutil >/dev/null && echo "hdiutil    ok (DMG packaging: make swift-app-dmg)" || echo "hdiutil    missing"
	@[ -f assets/icon/usbscope.icns ] && echo "icon       assets/icon/usbscope.icns present" || echo "icon       missing (the app bundle is built without one)"
	@[ -f SwiftTests/Golden/snapshot.json ] && echo "golden     frozen regression reference present" || echo "golden     MISSING"

env: ## print the toolchain versions used here
	@$(SWIFT) --version
	@xcodebuild -version 2>/dev/null | head -1 || true

build: ## build every product (swift build)
	$(SWIFT) build

test: ## run the Swift suite (swift test)
	$(SWIFT) test

check: ## all gates (build + tests + UI contract) — the CI equivalent
	$(MAKE) swift-test ui-contract

check-all: check ## alias for check (kept for the CI muscle memory)
	@true

clean: ## remove build output
	rm -rf .build .swiftpm
	rm -rf dist

distclean: clean ## clean plus the package caches
	rm -rf ~/.cache/org.swift.swiftpm

version: ## print the package version
	@echo $(VERSION)

## ---------------------------------------------------------------------------
## Swift products
## ---------------------------------------------------------------------------

swift: swift-build swift-test ## build and test everything

swift-build: ## build everything in the selected configuration (CONFIG=debug|release)
	$(SWIFT) build -c $(CONFIG)

swift-test: ## run the Swift suite (fixtures + frozen golden)
	$(SWIFT) test

swift-golden: ## re-record the golden from the fixtures (deliberate, env-gated)
	@echo "recording SwiftTests/Golden/snapshot.json from the fixtures…"
	@USBSCORE_REFRESH_GOLDEN=1 $(SWIFT) test --filter testFixtureSnapshotMatchesTheGolden 2>&1 \
		| grep -E "golden refreshed|error:" || true
	@git --no-pager diff --stat -- SwiftTests/Golden/snapshot.json
	@echo "review the diff, then commit it — the golden pins the JSON shape."

swift-run-app: swift-build ## run the SwiftUI app (usbscope-app)
	./.build/$(CONFIG)/usbscope-app

swift-app-check: swift-build ## headless self test of the app's data path (row counts per view)
	./.build/$(CONFIG)/usbscope-app --print-rows

swift-app-bundle: ## build dist/usbscope-swift.app (release, ad-hoc signed, verified)
	scripts/build-swift-app.sh

swift-app-dmg: ## pack the app into a compressed DMG (hdiutil, unsigned) + SHA256SUMS
	scripts/build-swift-dmg.sh

swift-app-smoke: swift-app-bundle ## exercise the installed app bundle, offscreen where supported
	scripts/smoke-swift-app.sh dist/usbscope-swift.app

swift-app-fixture-smoke: swift-app-bundle ## render every view from the frozen JSON fixture
	scripts/snapshot-fixture-smoke.sh dist/usbscope-swift.app SwiftTests/Golden/snapshot.json

ui-contract: ## verify keyboard, accessibility, navigation and snapshot hooks
	scripts/check-ui-contract.sh

run: swift-build ## run the CLI (overview)
	./.build/$(CONFIG)/usbscope

watch: swift-build ## run the CLI with live refresh every 2 s (Ctrl-C to stop)
	./.build/$(CONFIG)/usbscope --watch 2

## ---------------------------------------------------------------------------
## Docs assets
## ---------------------------------------------------------------------------

snapshot: swift-build ## render the app window to docs/screenshots/app-<view>.png (offscreen)
	@for view in ports cables devices thunderbolt power timeline security usb4 diff warnings; do \
		./.build/$(CONFIG)/usbscope-app --snapshot docs/screenshots/app-$$view.png --view $$view >/dev/null; \
		echo "docs/screenshots/app-$$view.png"; \
	done

checksums: ## verify dist/SHA256SUMS (written by scripts/build-swift-app.sh + build-swift-dmg.sh)
	@if [ -f dist/SHA256SUMS ]; then \
		cd dist && shasum -a 256 -c SHA256SUMS; \
	else \
		echo "no dist/SHA256SUMS yet — run: make swift-app-bundle"; exit 1; \
	fi

## ---------------------------------------------------------------------------
## Manual page & shell completions
## ---------------------------------------------------------------------------

man: ## install the CLI manual page into ~/.local/share/man/man1 (no sudo)
	@mkdir -p $(HOME)/.local/share/man/man1
	cp docs/man/usbscope.1 $(HOME)/.local/share/man/man1/usbscope.1
	@echo "installed: run 'man usbscope' (add ~/.local/share/man to MANPATH if needed)"

completions: ## install the zsh + bash completions into the user directories
	@mkdir -p $(HOME)/.zsh/completions $(HOME)/.local/share/bash-completion/completions
	cp scripts/completions/_usbscope $(HOME)/.zsh/completions/_usbscope
	cp scripts/completions/usbscope.bash $(HOME)/.local/share/bash-completion/completions/usbscope
	@echo "installed: zsh -> ~/.zsh/completions, bash -> ~/.local/share/bash-completion/completions"
