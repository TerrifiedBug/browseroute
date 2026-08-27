import AppKit
import BrowserouteCore

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
        statusController?.closePopover()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
