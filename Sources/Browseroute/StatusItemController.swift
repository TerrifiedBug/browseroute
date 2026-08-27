import AppKit
import BrowserouteCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var globalMonitor: Any?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = "browseroute-main"
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.branch",
                accessibilityDescription: "Browseroute",
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_: Notification) {
        removeMonitors()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let hosting = NSHostingController(
            rootView: MenuRootView(store: RoutingStore.shared) { [weak self] size in
                self?.applyPopoverSize(size)
            },
        )
        hosting.sizingOptions = .intrinsicContentSize
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hosting.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
    }

    /// `fittingSize` tracks the current window, so it never shrinks. Use the
    /// SwiftUI-reported size and let NSPopover keep the status-item anchor.
    private func applyPopoverSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.height >= 8 else { return }
        let ns = NSSize(width: max(ceil(size.width), 340), height: ceil(size.height))
        let sameWidth = abs(popover.contentSize.width - ns.width) < 0.5
        let sameHeight = abs(popover.contentSize.height - ns.height) < 0.5
        if sameWidth, sameHeight {
            return
        }
        popover.contentSize = ns
        popover.contentViewController?.preferredContentSize = ns
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] _ in
            if DefaultBrowser.isClaiming {
                return
            }
            self?.popover.performClose(nil)
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
