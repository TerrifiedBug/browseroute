#!/usr/bin/env bash
# Generate/refresh appcast.xml from the signed zips in build/ using Sparkle's
# generate_appcast tool. It EdDSA-signs each update with the private key in your
# Keychain (no Apple Developer ID involved).
#
# It first looks for generate_appcast on PATH, then inside .build/artifacts
# (downloaded automatically by `swift build` because Sparkle is an SPM dep), then
# at $SPARKLE_BIN. The first run creates the keypair if you don't have one and
# prints the public key — paste it into Resources/Info.plist (SUPublicEDKey).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GEN="$(command -v generate_appcast 2>/dev/null || true)"
[[ -z "$GEN" ]] && GEN="$(find "$ROOT/.build/artifacts" -name generate_appcast -type f 2>/dev/null | head -1)"
[[ -z "$GEN" && -n "${SPARKLE_BIN:-}" ]] && GEN="$SPARKLE_BIN/generate_appcast"
[[ -n "$GEN" && -x "$GEN" ]] || {
  echo "generate_appcast not found. Run 'swift build' first (downloads Sparkle's" >&2
  echo "tools into .build/artifacts), or set SPARKLE_BIN to Sparkle's bin dir." >&2
  exit 1
}

# Point enclosure URLs at the GitHub Release asset (not raw.githubusercontent,
# the tool's default), derived from the git remote + version. Override with
# DOWNLOAD_URL_PREFIX to host the zips elsewhere.
# shellcheck source=/dev/null
source "$ROOT/version.env" 2>/dev/null || true
PREFIX="${DOWNLOAD_URL_PREFIX:-}"
if [[ -z "$PREFIX" ]]; then
  REMOTE="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  SLUG="$(printf '%s' "$REMOTE" | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
  [[ -n "$SLUG" && -n "${MARKETING_VERSION:-}" ]] &&
    PREFIX="https://github.com/$SLUG/releases/download/v$MARKETING_VERSION/"
fi

GEN_ARGS=("$ROOT/build" -o "$ROOT/appcast.xml")
if [[ -n "$PREFIX" ]]; then
  GEN_ARGS+=(--download-url-prefix "$PREFIX")
else
  echo "==> note: no git remote/version; appcast URLs are relative. Set DOWNLOAD_URL_PREFIX." >&2
fi

# Sign with the Keychain key locally, or a private key piped from
# $SPARKLE_PRIVATE_KEY (set that as a CI secret for headless releases — no
# Keychain needed).
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GEN" "${GEN_ARGS[@]}" --ed-key-file -
else
  "$GEN" "${GEN_ARGS[@]}"
fi
echo "wrote $ROOT/appcast.xml"
