import AppKit
import BrowserouteCore
import ServiceManagement
import SwiftUI

struct MenuRootView: View {
    @Bindable var store: RoutingStore
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var isDefaultBrowser = false
    @State private var launchAtLogin = false
    @State private var installed: [InstalledBrowser] = []
    @State private var selectedBundleId: String?

    var body: some View {
        Group {
            if let selectedBundleId {
                BrowserDetailView(store: store, bundleId: selectedBundleId) {
                    self.selectedBundleId = nil
                }
            } else {
                rootContent
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PopoverSizeKey.self, value: geo.size)
            }
        }
        .onPreferenceChange(PopoverSizeKey.self, perform: onSizeChange)
        .task { refresh() }
    }

    private var rootContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.config.browsers.isEmpty {
                emptyState
            } else {
                browserList
                if store.config.defaultBrowserId == nil {
                    healthHint
                }
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("Browseroute")
                    .font(.headline)
                Spacer(minLength: 8)
                Toggle("Routing", isOn: routingBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                    .help(store.routingEnabled ? "Pause routing" : "Resume routing")
            }
            Text(lastRoutedCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var lastRoutedCaption: String {
        if !store.routingEnabled {
            let id = store.config.defaultBrowserId ?? store.config.browsers.first?.id
            if let id {
                let name = BrowserLauncher.displayName(forBundleIdentifier: id)
                return "Paused — all links open in \(name)"
            }
            return "Routing paused"
        }
        guard let last = Router.shared.lastRouted else {
            return "No links routed yet"
        }
        let host = last.url.host ?? last.url.absoluteString
        let name = BrowserLauncher.displayName(forBundleIdentifier: last.destination)
        return "\(host) → \(name)"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 36, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Route links to the right browser")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Add your browsers, then set one as the default catch-all.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            addBrowserMenu
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(16)
    }

    private var browserList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.config.browsers) { browser in
                Button {
                    selectedBundleId = browser.id
                } label: {
                    browserRow(browser)
                }
                .buttonStyle(.plain)
            }
            if !availableBrowsers.isEmpty {
                addBrowserMenu
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 6)
    }

    private func browserRow(_ browser: BrowserRule) -> some View {
        HStack(spacing: 10) {
            appIcon(for: browser.id)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(BrowserLauncher.displayName(forBundleIdentifier: browser.id))
                    .font(.body)
                Text(browser.patterns.count == 1 ? "1 rule" : "\(browser.patterns.count) rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if browser.id == store.config.defaultBrowserId {
                Text("Default")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var healthHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("No catch-all set — unmatched links open in the first browser.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            settingsMenu
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var settingsMenu: some View {
        Menu("Settings") {
            Toggle("Launch at Login", isOn: launchAtLoginBinding)
            if isDefaultBrowser {
                Toggle("Default Browser", isOn: .constant(true))
                    .help("Browseroute is already your default browser")
            } else {
                Button("Set as Default Browser…", action: becomeDefaultBrowser)
            }
            Button("Check for Updates…", action: AppServices.updater.checkForUpdates)
                .disabled(!AppServices.updater.canCheckForUpdates)
            Divider()
            Button("About Browseroute", action: showAbout)
        }
    }

    private var addBrowserMenu: some View {
        Menu("Add Browser…", systemImage: "plus") {
            ForEach(availableBrowsers) { browser in
                Button {
                    store.addBrowser(bundleId: browser.id)
                } label: {
                    Label {
                        Text(browser.name)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: browser.appURL.path))
                    }
                }
            }
        }
        .controlSize(.small)
    }

    private var availableBrowsers: [InstalledBrowser] {
        let added = Set(store.config.browsers.map(\.id))
        return installed.filter { !added.contains($0.id) }
    }

    private var routingBinding: Binding<Bool> {
        Binding(
            get: { store.routingEnabled },
            set: { store.setRoutingEnabled($0) },
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { setLaunchAtLogin($0) },
        )
    }

    private func refresh() {
        isDefaultBrowser = Self.checkIsDefaultBrowser()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        installed = BrowserLauncher.installedBrowsers()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppNotify.post(body: error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func becomeDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        Task {
            // Claim both schemes. Skip the immediate post-https probe: LaunchServices
            // may not have propagated http yet, so that skip is a race. Stop on the
            // first error so cancelling https does not also prompt for http.
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            } catch {
                AppNotify.post(body: "Could not become default browser: \(error.localizedDescription)")
            }
            isDefaultBrowser = Self.checkIsDefaultBrowser()
        }
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Browseroute",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? BrowserouteCore.fallbackVersion,
        ])
    }

    private static func isDefaultHandler(forScheme scheme: String) -> Bool {
        guard let probe = URL(string: "\(scheme)://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else {
            return false
        }
        return handler.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    private static func checkIsDefaultBrowser() -> Bool {
        isDefaultHandler(forScheme: "https") && isDefaultHandler(forScheme: "http")
    }
}

struct BrowserDetailView: View {
    @Bindable var store: RoutingStore
    let bundleId: String
    var onBack: () -> Void
    @State private var newPattern = ""
    @State private var hoveredPattern: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            patternList
            addField
            Divider()
            Button("Remove Browser", role: .destructive) {
                store.removeBrowser(bundleId: bundleId)
                onBack()
            }
            .controlSize(.small)
            .padding(14)
        }
    }

    private var browser: BrowserRule? {
        store.config.browsers.first { $0.id == bundleId }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(
                action: { onBack() },
                label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                },
            )
            .buttonStyle(.plain)
            .help("Back")
            .accessibilityLabel("Back")
            appIcon(for: bundleId)
                .frame(width: 28, height: 28)
            Text(BrowserLauncher.displayName(forBundleIdentifier: bundleId))
                .font(.headline)
            Spacer()
            Toggle("Default catch-all", isOn: defaultBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var defaultBinding: Binding<Bool> {
        Binding(
            get: { store.config.defaultBrowserId == bundleId },
            set: {
                if $0 {
                    store.setDefault(bundleId: bundleId)
                }
            },
        )
    }

    private var patternList: some View {
        let patterns = browser?.patterns ?? []
        return Group {
            if patterns.isEmpty {
                Text("No rules yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(patterns.enumerated()), id: \.offset) { index, pattern in
                        HStack {
                            Text(pattern)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button {
                                store.removePattern(at: index, from: bundleId)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(hoveredPattern == index ? 1 : 0)
                            .accessibilityLabel("Remove pattern")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredPattern = hovering ? index : nil
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var addField: some View {
        TextField("example.com or github.com/org/*", text: $newPattern)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                store.addPattern(newPattern, to: bundleId)
                newPattern = ""
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

@MainActor
private func appIcon(for bundleId: String) -> some View {
    let image: NSImage = {
        if let url = BrowserLauncher.applicationURL(forBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(size: NSSize(width: 20, height: 20))
    }()
    return Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
}

private struct PopoverSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
