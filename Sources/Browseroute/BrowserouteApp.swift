import AppKit
import SwiftUI

@main
@MainActor
struct BrowserouteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI needs at least one Scene. The popover is an NSPopover from
        // StatusItemController; this 1×1 window only keeps the lifecycle alive.
        WindowGroup("BrowserouteKeepalive") {
            KeepaliveView()
        }
        .windowResizability(.contentSize)
    }
}

private struct KeepaliveView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                for window in NSApplication.shared.windows where window.title == "BrowserouteKeepalive" {
                    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                    window.alphaValue = 0
                    window.ignoresMouseEvents = true
                }
            }
    }
}
