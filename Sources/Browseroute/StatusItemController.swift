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
        let hosting = FittingHost(rootView: MenuRootView(store: RoutingStore.shared))
        hosting.popover = popover
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hosting.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] _ in
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

/// NSPopover sizes once unless `contentSize` is pushed after SwiftUI relayouts.
/// Shrinking must keep the top edge (`frame.maxY`) so the header is not clipped.
private final class FittingHost<Content: View>: NSHostingController<Content> {
    weak var popover: NSPopover?

    override func viewDidLayout() {
        super.viewDidLayout()
        var size = view.fittingSize
        guard size.width.isFinite, size.height.isFinite, size.width >= 8, size.height >= 8 else { return }
        size.width = max(size.width, 340)
        size.height = ceil(size.height)
        let window = view.window
        let oldMaxY = window?.frame.maxY
        if preferredContentSize != size {
            preferredContentSize = size
            popover?.contentSize = size
        }
        if let window, let oldMaxY {
            var frame = window.frame
            frame.origin.y = oldMaxY - frame.height
            if frame != window.frame {
                window.setFrame(frame, display: true, animate: false)
            }
        }
        view.setFrameOrigin(.zero)
    }
}
