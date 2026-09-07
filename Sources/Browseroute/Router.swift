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
    private(set) var lastRouted: (urls: [URL], destination: String)?

    /// Every URL is forwarded: rules decide http(s), everything else goes to
    /// the catch-all. URLs sharing a destination open together so tab order
    /// matches the order they arrived in.
    func route(_ urls: [URL]) {
        var groups: [(destination: String, urls: [URL])] = []
        for url in urls {
            let dest = destination(for: url)
            if let index = groups.firstIndex(where: { $0.destination == dest }) {
                groups[index].urls.append(url)
            } else {
                groups.append((dest, [url]))
            }
        }
        let fallback = store.config.catchAllBrowserId
        for group in groups {
            let label = URLLabel.label(for: group.urls)
            if store.routingEnabled {
                log.info("Routing \(label, privacy: .public) -> \(group.destination, privacy: .public)")
            } else {
                log.info("Paused \(label, privacy: .public) -> \(group.destination, privacy: .public)")
            }
            Task { await open(group.urls, destination: group.destination, fallback: fallback) }
        }
    }

    private func destination(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let isWeb = scheme == "http" || scheme == "https"
        guard store.routingEnabled, isWeb else {
            return store.config.catchAllBrowserId
        }
        let unwrapped = CompiledRules.unwrap(url)
        if unwrapped.absoluteString != url.absoluteString {
            log.info(
                "Unwrapped \(url.host ?? "", privacy: .public) -> \(unwrapped.host ?? "(none)", privacy: .public)",
            )
        }
        return store.compiled.destination(for: url)
    }

    private func open(_ urls: [URL], destination: String, fallback: String) async {
        let outcome = await BrowserLauncher.open(urls, destination: destination, fallback: fallback)
        if outcome.opened {
            lastRouted = (urls, outcome.destination)
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
