import Foundation
import Observation

@MainActor
@Observable
public final class RoutingStore {
    public static let shared = RoutingStore()
    public static let defaultsKey = "routingConfig"
    public static let enabledKey = "routingEnabled"

    public private(set) var config: RoutingConfig
    public private(set) var compiled: CompiledRules
    public private(set) var routingEnabled: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults) ?? RoutingConfig()
        config = loaded
        compiled = CompiledRules(config: loaded)
        if defaults.object(forKey: Self.enabledKey) == nil {
            routingEnabled = true
        } else {
            routingEnabled = defaults.bool(forKey: Self.enabledKey)
        }
    }

    public func addBrowser(bundleId: String) {
        guard !config.browsers.contains(where: { $0.id == bundleId }) else { return }
        config.browsers.append(BrowserRule(id: bundleId))
        persist()
    }

    public func removeBrowser(bundleId: String) {
        let hadDefault = config.defaultBrowserId == bundleId
        config.browsers.removeAll { $0.id == bundleId }
        if hadDefault {
            config.defaultBrowserId = nil
        }
        persist()
    }

    public func setDefault(bundleId: String) {
        config.defaultBrowserId = bundleId
        persist()
    }

    public func setRoutingEnabled(_ enabled: Bool) {
        routingEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    public func addPattern(_ raw: String, to bundleId: String) {
        let pattern = Self.normalizePattern(raw)
        guard !pattern.isEmpty else { return }
        guard let index = config.browsers.firstIndex(where: { $0.id == bundleId }) else { return }
        guard !config.browsers[index].patterns.contains(pattern) else { return }
        for i in config.browsers.indices where i != index {
            config.browsers[i].patterns.removeAll { $0 == pattern }
        }
        config.browsers[index].patterns.append(pattern)
        persist()
    }

    public func removePattern(at index: Int, from bundleId: String) {
        guard let browserIndex = config.browsers.firstIndex(where: { $0.id == bundleId }) else { return }
        guard config.browsers[browserIndex].patterns.indices.contains(index) else { return }
        config.browsers[browserIndex].patterns.remove(at: index)
        persist()
    }

    private func persist() {
        compiled = CompiledRules(config: config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(raw, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> RoutingConfig? {
        guard let raw = defaults.string(forKey: defaultsKey),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(RoutingConfig.self, from: data)
    }

    /// Lowercase, trim, strip scheme/query/fragment/trailing slashes so a pasted
    /// `https://example.com/path/` becomes `example.com/path`.
    nonisolated static func normalizePattern(_ raw: String) -> String {
        var pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = pattern.range(of: "://") {
            pattern = String(pattern[scheme.upperBound...])
        }
        if pattern.hasPrefix("//") {
            pattern.removeFirst(2)
        }
        if let cut = pattern.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            pattern = String(pattern[..<cut])
        }
        while pattern.hasSuffix("/") {
            pattern.removeLast()
        }
        return pattern
    }
}
