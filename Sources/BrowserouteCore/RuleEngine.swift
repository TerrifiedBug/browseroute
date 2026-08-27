import Foundation

public struct RoutingConfig: Codable, Equatable, Sendable {
    public var browsers: [BrowserRule]
    public var defaultBrowserId: String?

    public init(browsers: [BrowserRule] = [], defaultBrowserId: String? = nil) {
        self.browsers = browsers
        self.defaultBrowserId = defaultBrowserId
    }
}

public struct BrowserRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var patterns: [String]

    public init(id: String, patterns: [String] = []) {
        self.id = id
        self.patterns = patterns
    }
}

public struct CompiledRules: @unchecked Sendable {
    private enum Kind {
        case hostSuffix(String)
        case hostGlob(NSRegularExpression)
        case hostPathGlob(NSRegularExpression)
    }

    private struct Entry {
        var bundleId: String
        var kind: Kind
    }

    private let entries: [Entry]
    private let fallback: String

    public init(config: RoutingConfig) {
        var compiled: [Entry] = []
        for browser in config.browsers {
            for raw in browser.patterns {
                let pattern = raw.lowercased()
                if pattern.contains("/") {
                    var glob = pattern
                    if !glob.hasSuffix("*") {
                        glob.append("*")
                    }
                    if let regex = Self.compileGlob(glob) {
                        compiled.append(Entry(bundleId: browser.id, kind: .hostPathGlob(regex)))
                    }
                } else if pattern.contains("*") {
                    if let regex = Self.compileGlob(pattern) {
                        compiled.append(Entry(bundleId: browser.id, kind: .hostGlob(regex)))
                    }
                } else if !pattern.isEmpty {
                    compiled.append(Entry(bundleId: browser.id, kind: .hostSuffix(pattern)))
                }
            }
        }
        entries = compiled
        fallback = config.defaultBrowserId ?? config.browsers.first?.id ?? "com.apple.Safari"
    }

    /// Peel one Outlook SafeLinks wrapper so matching uses the inner host.
    public static func unwrap(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "safelinks.protection.outlook.com"
              || host.hasSuffix(".safelinks.protection.outlook.com")
        else { return url }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name.lowercased() == "url" })?.value,
              let inner = URL(string: raw),
              let scheme = inner.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              inner.host != nil
        else { return url }
        return inner
    }

    public func destination(for url: URL) -> String {
        let url = Self.unwrap(url)
        guard let host = url.host, !host.isEmpty else {
            return fallback
        }
        let hostLower = host.lowercased()
        let hostPath = host + url.path
        for entry in entries {
            switch entry.kind {
            case let .hostSuffix(entryHost):
                if hostLower == entryHost || hostLower.hasSuffix("." + entryHost) {
                    return entry.bundleId
                }
            case let .hostGlob(regex):
                if Self.matches(regex, host) {
                    return entry.bundleId
                }
            case let .hostPathGlob(regex):
                if Self.matches(regex, hostPath) {
                    return entry.bundleId
                }
            }
        }
        return fallback
    }

    private static func compileGlob(_ pattern: String) -> NSRegularExpression? {
        var regex = ""
        var remainder = pattern[...]
        while let star = remainder.firstIndex(of: "*") {
            regex += NSRegularExpression.escapedPattern(for: String(remainder[..<star]))
            regex += ".*"
            remainder = remainder[remainder.index(after: star)...]
        }
        regex += NSRegularExpression.escapedPattern(for: String(remainder))
        return try? NSRegularExpression(pattern: "^\(regex)$", options: [.caseInsensitive])
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
}
