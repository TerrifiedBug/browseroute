import AppKit
import BrowserouteCore
import Observation
import os
import UserNotifications

private let log = Logger(subsystem: "com.terrifiedbug.browseroute", category: "Router")

@MainActor
@Observable
final class Router {
    static let shared = Router()

    var store: RoutingStore = .shared
    private(set) var lastRouted: (url: URL, destination: String)?

    func route(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            log.info("Dropped non-http scheme \(scheme, privacy: .public)")
            return
        }
        let matched = CompiledRules.unwrap(url)
        let dest: String = if store.routingEnabled {
            store.compiled.destination(for: url)
        } else {
            store.config.defaultBrowserId ?? store.config.browsers.first?.id ?? "com.apple.Safari"
        }
        let fallback = store.config.defaultBrowserId ?? dest
        let host = matched.host ?? "(none)"
        if matched.absoluteString != url.absoluteString {
            log.info("Unwrapped \(url.host ?? "", privacy: .public) -> \(host, privacy: .public)")
        }
        if store.routingEnabled {
            log.info("Routing \(host, privacy: .public) -> \(dest, privacy: .public)")
        } else {
            log.info("Paused \(host, privacy: .public) -> \(dest, privacy: .public)")
        }
        Task { await open(url, destination: dest, fallback: fallback) }
    }

    private func open(_ url: URL, destination: String, fallback: String) async {
        let outcome = await BrowserLauncher.open(url, destination: destination, fallback: fallback)
        if outcome.opened {
            lastRouted = (url, outcome.destination)
        }
        if let message = outcome.notification {
            AppNotify.post(body: message)
        }
    }
}

enum AppNotify {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(title: String = "Browseroute", body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "browseroute.notice",
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
    }
}
