# usbscope — developer tasks
#
# Every target is self documenting: `make` (or `make help`) lists them grouped by
# section, and the `##` comment next to a target is the description. Commands run
# through `uv`, so the pinned Python 3.14 and the locked dependencies are used.
#
# A Makefile variable (not an environment one, which macOS may already define):
#   SHOT_HOST=macbook make refresh-screenshots

SHELL := /bin/bash
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

UV ?= uv
PY ?= $(UV) run python
SHOT_HOST ?= mac
VERSION := $(shell $(PY) -c "import usbscope; print(usbscope.__version__)" 2>/dev/null || echo unknown)

.PHONY: help doctor sync test lint format check coverage run watch run-app \
        refresh-screenshots screenshots snapshot icon binary app-bundle app dmg artifacts \
        checksums ci mas-pkg mas-pkg-dry mas-screenshots install clean distclean env version \
        swift swift-build swift-test swift-golden swift-run-app swift-app-check swift-app-bundle \
        man completions check-all

## ---------------------------------------------------------------------------
## Setup & quality
## ---------------------------------------------------------------------------

help: ## show this help
	@printf '\nusbscope %s — make targets\n\n' "$(VERSION)"
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\n  variables: SHOT_HOST=%s (host name shown in screenshots), VERSION=%s\n\n' "$(SHOT_HOST)" "$(VERSION)"

doctor: ## check the tools this repo needs (uv, librsvg, codesign, hdiutil)
	@command -v $(UV) >/dev/null && echo "uv         $(shell $(UV) --version | cut -d' ' -f2)" || echo "uv         MISSING"
	@$(PY) -c "import rich, usbscope; print('runtime    rich + usbscope ok')" 2>/dev/null || echo "runtime    MISSING (run: make sync)"
	@$(PY) -c "import AppKit; print('appkit     available (usbscope-app)')" 2>/dev/null || echo "appkit     missing — make sync installs the macapp extra"
	@command -v rsvg-convert >/dev/null && echo "librsvg    ok (screenshot PNGs)" || echo "librsvg    missing — brew install librsvg (only needed for make screenshots)"
	@command -v codesign >/dev/null && echo "codesign   ok (ad-hoc app signature)" || echo "codesign   missing"
	@command -v hdiutil >/dev/null && echo "hdiutil    ok (DMG packaging)" || echo "hdiutil    missing"

sync: ## install the environment (dev tools + the macapp extra)
	$(UV) sync --extra macapp

env: ## print the toolchain versions used here
	@$(UV) --version
	@$(PY) -c "import sys; print('python     ', sys.version.split()[0])"
	@$(UV) run ruff --version
	@$(UV) run ty --version
	@$(UV) run pytest --version
	@$(PY) -c "import objc; print('pyobjc     ', objc.__version__)" 2>/dev/null || true

format: ## format and auto-fix the code (ruff)
	$(UV) run ruff format
	$(UV) run ruff check --fix

lint: ## static checks (ruff format --check, ruff check, ty)
	$(UV) run ruff format --check
	$(UV) run ruff check
	$(UV) run ty check

test: ## run the test suite
	$(UV) run pytest

coverage: ## run the tests with a coverage report for src/usbscope
	$(UV) run --with pytest-cov pytest --cov=usbscope --cov-report=term-missing

check: ## all gates: format check, lint, types, tests (CI equivalent)
	$(MAKE) lint
	$(MAKE) test

check-all: check swift-test ## every gate incl. the Swift port (Python + Swift)

## ---------------------------------------------------------------------------
## Run
## ---------------------------------------------------------------------------

run: ## run the CLI (overview)
	$(UV) run usbscope

watch: ## run the CLI with live refresh every 2 s
	$(UV) run usbscope --watch 2

run-app: ## run the native macOS app from the checkout
	$(UV) run --extra macapp usbscope-app

## ---------------------------------------------------------------------------
## Screenshots & docs assets
## ---------------------------------------------------------------------------

snapshot: ## render the app window to docs/screenshots/app-<view>.png (offscreen)
	@for view in ports cables devices thunderbolt power; do \
		$(UV) run --extra macapp usbscope-app --snapshot docs/screenshots/app-$$view.png --view $$view >/dev/null; \
		echo "docs/screenshots/app-$$view.png"; \
	done

refresh-screenshots: ## regenerate the CLI screenshots (SVG + PNG, host name masked)
	$(UV) run python scripts/screenshots.py --png --host $(SHOT_HOST)

screenshots: refresh-screenshots snapshot ## regenerate every screenshot in the docs

## ---------------------------------------------------------------------------
## Build artifacts
## ---------------------------------------------------------------------------

binary: ## build the standalone CLI binary (dist/usbscope-<version>-macos-<arch>)
	$(UV) run python scripts/build_binary.py

icon: ## regenerate the app icon (assets/icon/usbscope.icns) from the SVG
	$(UV) run python scripts/make_icon.py

app-bundle: icon ## build usbscope.app (with icon) and the styled DMG into dist/
	$(UV) run python scripts/build_app.py

app: app-bundle ## alias for app-bundle

dmg: ## rebuild only the DMG for an existing dist/usbscope.app
	$(UV) run python scripts/make_dmg.py dist/usbscope.app \
		"dist/usbscope-$(VERSION)-macos-$$(uname -m).dmg" --volume-name usbscope

artifacts: check binary app-bundle ## full release build: gates, CLI binary, app + DMG

ci: check ## what the GitHub Actions workflow runs (alias for check)

mas-pkg: ## package for the Mac App Store (needs Apple Distribution certificates)
	$(UV) run python scripts/make_mas_pkg.py

mas-pkg-dry: ## show the App Store packaging commands without running them
	$(UV) run python scripts/make_mas_pkg.py --dry-run

mas-screenshots: snapshot ## App Store screenshots (16:10, no alpha) into docs/screenshots/asc-*
	@command -v magick >/dev/null || { echo "ImageMagick (magick) is required"; exit 1; }
	@for spec in "1440x900:ports" "1280x800:devices"; do \
		size=$${spec%%:*}; view=$${spec##*:}; \
		magick docs/screenshots/app-$$view.png -background "#1e1e1e" -alpha remove -alpha off \
			-resize $$size -gravity north -extent $$size docs/screenshots/asc-$$size.png; \
		echo "docs/screenshots/asc-$$size.png"; \
	done

checksums: ## verify the checksums of everything in dist/
	@cd dist && for f in SHA256SUMS SHA256SUMS-app; do \
		[ -f $$f ] && shasum -a 256 -c $$f || echo "no $$f yet (run make artifacts)"; \
	done

install: ## install the CLI (and the app entry point) as uv tools
	$(UV) tool install --force '.[macapp]'

## ---------------------------------------------------------------------------
## Swift port
## ---------------------------------------------------------------------------

swift: swift-build swift-test ## build and test the Swift port

swift-build: ## build the Swift port (swift build)
	swift build

swift-test: ## run the Swift suite (JSON parity against the Python golden)
	swift test

swift-golden: ## regenerate the parity golden from the fixtures (Python side)
	$(UV) run python scripts/swift_golden.py

swift-run-app: swift-build ## run the SwiftUI app (usbscope-app)
	./.build/debug/usbscope-app

swift-app-check: swift-build ## headless self test of the app's data path (row counts per view)
	./.build/debug/usbscope-app --print-rows

swift-app-bundle: ## build the SwiftUI app into dist/usbscope-swift.app (release, ad-hoc signed)
	$(UV) run python scripts/build_swift_app.py

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

## ---------------------------------------------------------------------------
## Housekeeping
## ---------------------------------------------------------------------------

clean: ## remove build and dist output
	rm -rf build dist .pytest_cache .ruff_cache
	find . -name __pycache__ -type d -prune -exec rm -rf {} +

distclean: clean ## clean plus the virtualenv and caches
	rm -rf .venv ~/.cache/uv

version: ## print the package version
	@echo $(VERSION)
