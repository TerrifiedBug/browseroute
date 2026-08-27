# Changelog

All notable changes to Browseroute are documented here (Keep a Changelog style).

## 0.1.0 — Unreleased
- Route `http`/`https` links as the macOS default browser from rules edited in the menu-bar popover.
- Host suffix, host glob, and host+path glob matching, with a Default catch-all.
- Launch at login via `SMAppService`.
- Header **Routing** switch pauses matching (all links go to the catch-all).
- Settings menu: launch at login, default-browser, check for updates, About.
- Unwrap Outlook SafeLinks so matching uses the inner host.
- Click outside the popover to dismiss it.

- Developer ID-signed, notarized GitHub releases (same methodology as yap and TickerBar) and a Homebrew cask.
- Sparkle is an SPM dependency on the app target so Check for Updates can run once `SUPublicEDKey` is a real EdDSA key.
