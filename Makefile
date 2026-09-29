.PHONY: run test smoke smoke-l10n build app dmg pkg clean

run: patch
	swift run Tappy

test: patch
	swift run TappyChecks

smoke: patch
	swift build
	./Scripts/smoke.sh

# Full E2E in every supported language (7 × ~15 s): exercises the
# localized Done button, the identifier-driven AX presses, and asserts
# the app actually resolved each requested localization.
smoke-l10n: patch
	swift build
	@set -e; for lang in en zh-Hans ja ko es fr de; do \
		echo "=== smoke $$lang ==="; \
		TAPPY_SMOKE_LANG=$$lang ./Scripts/smoke.sh || exit 1; \
	done

bench: patch
	swift run -c release TappyBench

build: patch
	swift build -c release

# Strips Xcode-only #Preview blocks from SwiftPM checkouts (CLT builds).
patch:
	./Scripts/patch-deps.sh

app: build
	./Scripts/bundle.sh

dmg: app
	./Scripts/make-dmg.sh

# Mac App Store package (requires distribution identities in the
# signing config; see docs/signing.md).
pkg: build
	./Scripts/make-pkg.sh

clean:
	rm -rf .build build
