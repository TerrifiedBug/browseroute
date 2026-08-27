APP_NAME := Browseroute

.PHONY: build test check format lint run package release install clean

build:
	swift build

test:
	swift test

lint:
	swiftformat Sources Tests --lint
	swiftlint --strict

format:
	swiftformat Sources Tests

check: lint test

# Build a debug .app and launch it in the menu bar.
run:
	./Scripts/compile_and_run.sh

# Copy the packaged .app to /Applications (needed for default-browser registration).
install:
	./Scripts/package_app.sh debug
	pkill -x Browseroute || true
	rm -rf /Applications/Browseroute.app
	cp -R build/Browseroute.app /Applications/Browseroute.app
	xattr -dr com.apple.quarantine /Applications/Browseroute.app 2>/dev/null || true

# Universal release .app (ad-hoc signed, for local inspection).
package:
	./Scripts/package_app.sh release

# Developer ID sign + notarize + zip. Same script CI runs on v* tags.
# Requires APP_IDENTITY and a notarytool profile (see Scripts/build-release.sh).
release:
	./Scripts/build-release.sh

clean:
	swift package clean
	rm -rf build dist
