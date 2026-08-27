import AppKit
import BrowserouteCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private let updater: any UpdaterProviding = makeUpdater()

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppServices.updater = updater
        AppNotify.requestAuthorization()
        statusController = StatusItemController()
        updater.start()
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            Router.shared.route(url)
        }
    }

    func applicationDidResignActive(_: Notification) {
        // The default-browser prompt deactivates us. Closing the popover then
        // makes LaunchServices treat the request as cancelled.
        if DefaultBrowser.isClaiming {
            return
        }
        statusController?.closePopover()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

/// Claims http/https as the default handler. Lives off the SwiftUI view so the
/// system prompt is not cancelled when the transient popover closes.
@MainActor
enum DefaultBrowser {
    private static let log = Logger(subsystem: "com.terrifiedbug.browseroute", category: "DefaultBrowser")
    private(set) static var isClaiming = false

    static func isCurrent() -> Bool {
        isHandler(forScheme: "https") && isHandler(forScheme: "http")
    }

    static func isHandler(forScheme scheme: String) -> Bool {
        guard let probe = URL(string: "\(scheme)://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else {
            return false
        }
        return handler.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    static func claim() async {
        guard !isClaiming else { return }
        isClaiming = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            NSApp.setActivationPolicy(.accessory)
            isClaiming = false
        }
        // Let the popover finish dismissing so the confirmation dialog can appear.
        try? await Task.sleep(for: .milliseconds(250))
        let appURL = Bundle.main.bundleURL
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            log.info("claimed http and https")
        } catch {
            let ns = error as NSError
            log.error(
                "claim failed \(ns.domain, privacy: .public) \(ns.code) \(error.localizedDescription, privacy: .public)",
            )
            if ns.domain == CocoaError.errorDomain, ns.code == CocoaError.userCancelled.rawValue {
                return
            }
            AppNotify.post(body: "Could not become default browser: \(error.localizedDescription)")
        }
    }
}
