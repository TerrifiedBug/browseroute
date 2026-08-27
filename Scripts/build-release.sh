#!/usr/bin/env bash
#
# Build, Developer ID-sign, notarize and package Browseroute.app into
# dist/Browseroute-<version>.zip. The release workflow runs this same script,
# so a local run and a CI run produce the same artifact.
#
# SwiftPM has no archive/export path, so signing is inside-out by hand:
# Sparkle nested code (if present), then Sparkle.framework, then the app.
# Never `codesign --deep` — Sparkle's XPC services have different requirements
# (see Sparkle docs; TickerBar's release script has the same rule).
#
# Configuration, all via environment:
#   VERSION          release version, e.g. 0.1.0 (default: version.env)
#   APP_IDENTITY     "Developer ID Application: NAME (TEAMID)"
#   NOTARY_PROFILE   notarytool keychain profile (default: browseroute-notary)
#   SKIP_NOTARIZE=1  build and sign, but do not notarize (local testing)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=/dev/null
source "$ROOT/version.env"

VERSION="${VERSION:-$MARKETING_VERSION}"
APP_IDENTITY="${APP_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-browseroute-notary}"

APP_NAME="Browseroute"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

if [[ -z "$APP_IDENTITY" ]]; then
  echo "APP_IDENTITY is unset." >&2
  echo "Set it to your Developer ID Application identity, e.g.:" >&2
  echo '  APP_IDENTITY="Developer ID Application: Your Name (TEAMID)"' >&2
  echo "List what you have with: security find-identity -v -p codesigning" >&2
  exit 1
fi

step "Stamping version $VERSION"
sed -i '' "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$VERSION/" "$ROOT/version.env"

step "Building universal .app"
"$ROOT/Scripts/package_app.sh" release

step "Copying to dist"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$ROOT/build/$APP_NAME.app" "$APP"
xattr -cr "$APP"

sign() {
  codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$@"
}

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  step "Codesigning Sparkle (inside-out, no --deep)"
  # Nested bundles first: XPCServices/*.xpc and Updater.app.
  while IFS= read -r -d '' nested; do
    sign "$nested"
  done < <(find "$SPARKLE" \( -name '*.xpc' -o -name '*.app' \) -print0)
  # Then bare Mach-O helpers beside them, i.e. Versions/B/Autoupdate. These
  # match neither *.xpc nor *.app, so they used to keep the ad-hoc signature
  # package_app.sh applies, and notarization rejected the whole archive with
  # "Autoupdate: The binary is not signed with a valid Developer ID
  # certificate", no secure timestamp and no hardened runtime. Nested bundles
  # are pruned: their main executables are signed with their bundle above.
  while IFS= read -r -d '' helper; do
    # A bare `grep -q ... && sign` would make the loop exit non-zero whenever
    # the last file is not Mach-O, and set -e would kill the script.
    if [[ "$(basename "$helper")" != "Sparkle" ]] && file -b "$helper" | grep -q 'Mach-O'; then
      sign "$helper"
    fi
  done < <(find "$SPARKLE" \( -name '*.xpc' -o -name '*.app' \) -prune -o -type f -print0)
  sign "$SPARKLE"
fi

step "Codesigning app (hardened runtime)"
sign "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "${SKIP_NOTARIZE:-}" == "1" ]]; then
  step "Skipping notarization (SKIP_NOTARIZE=1)"
  echo "WARNING: not notarized, local testing only. Gatekeeper will complain." >&2
else
  step "Notarizing"
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  # notarytool exits 0 even when the submission comes back Invalid, so the
  # status has to be read out. Without this the script walks on to stapler and
  # dies there with "Record not found", which says nothing about the cause.
  SUBMISSION="$(xcrun notarytool submit "$DIST/notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  rm -f "$DIST/notarize.zip"
  echo "$SUBMISSION"
  NOTARY_STATUS="$(sed -n 's/.*"status" *: *"\([^"]*\)".*/\1/p' <<<"$SUBMISSION" | tail -1)"
  if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "Notarization returned $NOTARY_STATUS, not Accepted." >&2
    SUBMISSION_ID="$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' <<<"$SUBMISSION" | head -1)"
    if [[ -n "$SUBMISSION_ID" ]]; then
      echo "Notary log for $SUBMISSION_ID:" >&2
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    exit 1
  fi

  step "Stapling"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  # Must report "source=Notarized Developer ID". Anything else means users get
  # a Gatekeeper prompt, so fail here rather than ship it.
  spctl --assess --type execute --verbose=4 "$APP"
fi

step "Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Done"
echo "App: $APP"
echo "Zip: $ZIP"
echo "SHA256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
