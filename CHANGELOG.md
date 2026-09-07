# Changelog

All notable changes to Browseroute are documented here (Keep a Changelog style).

## 0.2.0 — 2026-09-07
- Forward every URL handed to Browseroute: local files (`.html` from Finder), other schemes, and unmatched links all open in the Default catch-all instead of being dropped.
- Open several links or files at once: they are grouped by destination and handed to each browser in arrival order.
- Fall back to the Default catch-all (with a notification) when the chosen browser cannot open an item, not just when it is missing.
- Listed in Finder's Open With for html, xhtml, svg, txt, js, css, xml, png, jpeg, gif, webp, avif, and pdf.

## 0.1.0 — 2026-08-27
- Route `http`/`https` links as the macOS default browser from rules edited in the menu-bar popover.
- Host suffix, host glob, and host+path glob matching, with a Default catch-all.
- Launch at login via `SMAppService`.
- Header **Routing** switch pauses matching (all links go to the catch-all).
- Settings menu: launch at login, a checkmark when already the default browser, check for updates, About.
- Unwrap Outlook SafeLinks so matching uses the inner host.
- Click outside the popover to dismiss it.
- App icon: charcoal squircle with a routing Y (About, Finder, README).

- Developer ID-signed, notarized GitHub releases (same methodology as yap and TickerBar) and a Homebrew cask.
- Sparkle EdDSA key baked in; Check for Updates is live on Developer ID-signed GitHub builds (ad-hoc and Homebrew stay off). The cert check runs after launch and does not hash sealed resources.
- Release CI fails before notarize if `HOMEBREW_TAP_TOKEN` is missing, expired, or cannot push to the tap, or if the Developer ID identity does not validate in the build keychain.
