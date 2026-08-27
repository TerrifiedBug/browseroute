#!/usr/bin/env bash
# Dev loop: kill any running instance, build a debug .app, launch it, verify it
# stays up in the menu bar.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Browseroute"

pkill -x "$APP_NAME" 2>/dev/null || true

"$ROOT/Scripts/package_app.sh" debug
open "$ROOT/build/$APP_NAME.app"

sleep 2
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "✅ $APP_NAME is running in the menu bar."
else
  echo "❌ $APP_NAME failed to stay running." >&2
  exit 1
fi
