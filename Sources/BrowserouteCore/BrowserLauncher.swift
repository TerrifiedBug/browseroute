import AppKit
import os

private let log = Logger(subsystem: "com.terrifiedbug.browseroute", category: "Launcher")

public enum LaunchError: Error, LocalizedError {
    case browserNotFound(String)
    case openFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case let .browserNotFound(bundleId):
            "Browser \(bundleId) not found"
        case let .openFailed(bundleId, error):
            "Failed to open in \(bundleId): \(error.localizedDescription)"
        }
    }
}

public struct LaunchOutcome: Sendable, Equatable {
    public var opened: Bool
    public var destination: String
    public var notification: String?

    public init(opened: Bool, destination: String, notification: String? = nil) {
        self.opened = opened
        self.destination = destination
        self.notification = notification
    }
}

public enum URLLabel {
    /// "index.html", "example.com", "mailto:x@y.z", or "5 items". One line;
    /// callers truncate.
    public static func label(for urls: [URL]) -> String {
        if urls.count > 1 {
            return "\(urls.count) items"
        }
        guard let url = urls.first else {
            return ""
        }
        if url.isFileURL {
            let name = url.lastPathComponent
            return name.isEmpty ? url.path : name
        }
        switch url.scheme?.lowercased() {
        case "http", "https":
            return url.host ?? url.absoluteString
        default:
            return url.absoluteString
        }
    }
}

public struct InstalledBrowser: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let appURL: URL
}

@MainActor
public enum BrowserLauncher {
    private static var urlCache: [String: URL] = [:]

    public static func applicationURL(forBundleIdentifier bundleId: String) -> URL? {
        if let cached = urlCache[bundleId] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        urlCache[bundleId] = url
        return url
    }

    public static func displayName(forBundleIdentifier bundleId: String) -> String {
        if let bundle = applicationURL(forBundleIdentifier: bundleId).flatMap({ Bundle(url: $0) }) {
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
                return name
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                return name
            }
        }
        switch bundleId {
        case "com.google.Chrome": return "Chrome"
        case "io.island.Island": return "Island"
        default: return bundleId
        }
    }

    public static func installedBrowsers() -> [InstalledBrowser] {
        let probe = URL(string: "https://example.com")!
        let selfId = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [InstalledBrowser] = []
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard let id = Bundle(url: appURL)?.bundleIdentifier, !id.isEmpty else { continue }
            if id == selfId {
                continue
            }
            if !seen.insert(id).inserted {
                continue
            }
            result.append(InstalledBrowser(id: id, name: displayName(forBundleIdentifier: id), appURL: appURL))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func open(_ urls: [URL], withBundleIdentifier bundleId: String) async throws {
        guard let appURL = applicationURL(forBundleIdentifier: bundleId) else {
            throw LaunchError.browserNotFound(bundleId)
        }
        do {
            try await NSWorkspace.shared.open(
                urls,
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration(),
            )
        } catch {
            throw LaunchError.openFailed(bundleId, error)
        }
    }

    /// Open in `destination`, falling back to `fallback` when that browser is
    /// missing or cannot open the URLs.
    public static func open(
        _ urls: [URL],
        destination: String,
        fallback: String,
    ) async -> LaunchOutcome {
        do {
            try await open(urls, withBundleIdentifier: destination)
            return LaunchOutcome(opened: true, destination: destination)
        } catch {
            log.error("\(error.localizedDescription, privacy: .public)")
            let (missing, detail): (Bool, String) = switch error {
            case LaunchError.browserNotFound: (true, error.localizedDescription)
            case let LaunchError.openFailed(_, underlying): (false, underlying.localizedDescription)
            default: (false, error.localizedDescription)
            }
            let wanted = displayName(forBundleIdentifier: destination)
            let fallbackName = displayName(forBundleIdentifier: fallback)
            let label = URLLabel.label(for: urls)
            if destination != fallback {
                do {
                    try await open(urls, withBundleIdentifier: fallback)
                    return LaunchOutcome(
                        opened: true,
                        destination: fallback,
                        notification: missing
                            ? "Browser \(wanted) not found — opened in \(fallbackName)"
                            : "\(wanted) couldn't open \(label) — opened in \(fallbackName)",
                    )
                } catch {
                    log.error(
                        "Fallback \(fallback, privacy: .public) failed: \(error.localizedDescription, privacy: .public)",
                    )
                }
            }
            return LaunchOutcome(
                opened: false,
                destination: destination,
                notification: missing
                    ? "Browser \(fallbackName) not found — URL not opened"
                    : "\(wanted) couldn't open \(label): \(detail)",
            )
        }
    }
}
