#!/usr/bin/env bash
# Assemble Browseroute.app from `swift build` output. NOT xcodebuild.
#   ./Scripts/package_app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/version.env"

# Sparkle compares CFBundleVersion (the build number), NOT the marketing string,
# so it MUST increase every release or updates are never detected. Derive it from
# the git commit count — always monotonic, impossible to forget. Falls back to
# version.env's BUILD_NUMBER outside a git checkout.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo "$BUILD_NUMBER")"

CONFIG="${1:-debug}"
APP_NAME="Browseroute"
BUNDLE="$ROOT/build/$APP_NAME.app"
CONTENTS="$BUNDLE/Contents"

if [[ "$CONFIG" == "release" ]]; then
  BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)
else
  BUILD_FLAGS=()
fi

echo "==> swift build (${CONFIG})"
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "==> assembling $APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Info.plist: substitute the version into the committed template.
sed -e "s|__MARKETING_VERSION__|$MARKETING_VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"

# App icon, if built.
[[ -f "$ROOT/Icon.icns" ]] && cp "$ROOT/Icon.icns" "$CONTENTS/Resources/Icon.icns"

# SwiftPM resource bundles, if any.
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -e "$bundle" ]] && cp -R "$bundle" "$CONTENTS/Resources/"
done

# Embed Sparkle.framework if it was built into the artifacts.
SPARKLE="$(find "$BIN_DIR" -maxdepth 5 -name 'Sparkle.framework' -type d 2>/dev/null | head -1 || true)"
if [[ -n "$SPARKLE" ]]; then
  echo "==> embedding Sparkle.framework"
  rm -rf "$CONTENTS/Frameworks/Sparkle.framework"
  cp -R "$SPARKLE" "$CONTENTS/Frameworks/"
  # The binary loads Sparkle via @rpath, but SwiftPM only bakes in @loader_path
  # and toolchain rpaths. Without this the app crashes at launch with
  # "Library not loaded: @rpath/Sparkle.framework". Point it at the embedded copy.
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null || true
fi

# Ad-hoc sign so the dev build launches. Real signing: Scripts/build-release.sh.
echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "built: $BUNDLE"
