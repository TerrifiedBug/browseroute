#!/usr/bin/env bash
# Compile an app icon to Icon.icns.
#   • Icon.icon/   (Icon Composer source, macOS 15 / Xcode 16+) -> via `icon` tool
#   • Icon.iconset/ (classic) -> via iconutil
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -d "$ROOT/Icon.icon" ]] && xcrun --find icon >/dev/null 2>&1; then
  xcrun icon compile "$ROOT/Icon.icon" --output "$ROOT/Icon.icns"
elif [[ -d "$ROOT/Icon.iconset" ]]; then
  iconutil -c icns "$ROOT/Icon.iconset" -o "$ROOT/Icon.icns"
else
  echo "no Icon.icon/ or Icon.iconset/ found — add one, then re-run." >&2
  exit 1
fi

echo "wrote $ROOT/Icon.icns"
