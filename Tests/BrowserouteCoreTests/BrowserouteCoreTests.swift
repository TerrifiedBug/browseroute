@testable import BrowserouteCore
import Foundation
import Testing

private let chrome = "com.google.Chrome"
private let island = "io.island.Island"
private let safari = "com.apple.Safari"

private func url(_ raw: String) -> URL {
    URL(string: raw)!
}

private func dest(_ raw: String, _ config: RoutingConfig) -> String {
    CompiledRules(config: config).destination(for: url(raw))
}

@Test func `bare host matches apex and subdomains, case-insensitive`() {
    let config = RoutingConfig(browsers: [BrowserRule(id: island, patterns: ["example.com"])], defaultBrowserId: chrome)
    #expect(dest("https://example.com", config) == island)
    #expect(dest("https://a.example.com/x", config) == island)
    #expect(dest("https://A.EXAMPLE.COM", config) == island)
    #expect(dest("https://example.com", RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["EXAMPLE.COM"])],
        defaultBrowserId: chrome,
    )) == island)
}

@Test func `bare host is label-boundary only`() {
    let config = RoutingConfig(browsers: [BrowserRule(id: island, patterns: ["example.com"])], defaultBrowserId: chrome)
    #expect(dest("https://evil-example.com", config) == chrome)
    #expect(dest("https://example.com.evil.net", config) == chrome)
    #expect(dest("https://okta.com", RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["corp.okta.com"])],
        defaultBrowserId: chrome,
    )) == chrome)
}

@Test func `star glob matches host only, not apex`() {
    let config = RoutingConfig(browsers: [BrowserRule(id: island, patterns: ["*.corp.com"])], defaultBrowserId: chrome)
    #expect(dest("https://a.corp.com", config) == island)
    #expect(dest("https://a.b.corp.com/x", config) == island)
    #expect(dest("https://corp.com", config) == chrome)
}

@Test func `path glob matches host plus path, not other orgs`() {
    let explicit = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["github.com/org/*"])],
        defaultBrowserId: chrome,
    )
    let implicit = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["github.com/org"])],
        defaultBrowserId: chrome,
    )
    for config in [explicit, implicit] {
        #expect(dest("https://github.com/org/repo", config) == island)
        #expect(dest("https://github.com/other", config) == chrome)
        #expect(dest("https://github.com/other/x", config) == chrome)
    }
}

@Test func `matching is case-insensitive for host and path`() {
    let config = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["github.com/work-org/*"])],
        defaultBrowserId: chrome,
    )
    #expect(dest("https://GitHub.com/Work-Org/Repo", config) == island)
}

@Test func `first match in browser order wins`() {
    let config = RoutingConfig(
        browsers: [
            BrowserRule(id: island, patterns: ["overlap.com"]),
            BrowserRule(id: safari, patterns: ["overlap.com"]),
        ],
        defaultBrowserId: chrome,
    )
    #expect(dest("https://overlap.com/x", config) == island)
    #expect(dest("https://www.overlap.com", config) == island)
}

@Test func `personal exception wins when listed first`() {
    let config = RoutingConfig(
        browsers: [
            BrowserRule(id: chrome, patterns: ["personal.example-corp.com"]),
            BrowserRule(id: island, patterns: ["example-corp.com"]),
        ],
        defaultBrowserId: chrome,
    )
    #expect(dest("https://personal.example-corp.com", config) == chrome)
    #expect(dest("https://mail.example-corp.com", config) == island)
}

@Test func `no match uses defaultBrowserId`() {
    let config = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["work.example"])],
        defaultBrowserId: chrome,
    )
    #expect(dest("https://news.ycombinator.com", config) == chrome)
}

@Test func `nil default falls back to first browser`() {
    let config = RoutingConfig(browsers: [BrowserRule(id: island), BrowserRule(id: chrome)])
    #expect(dest("https://news.ycombinator.com", config) == island)
}

@Test func `empty config falls back to Safari`() {
    #expect(dest("https://example.com", RoutingConfig()) == safari)
}

@Test func `mailto uses fallback chain`() {
    let withDefault = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["example.com"])],
        defaultBrowserId: chrome,
    )
    #expect(dest("mailto:user@example.com", withDefault) == chrome)
    let firstBrowser = RoutingConfig(browsers: [BrowserRule(id: island), BrowserRule(id: chrome)])
    #expect(dest("mailto:user@example.com", firstBrowser) == island)
    #expect(dest("mailto:user@example.com", RoutingConfig()) == safari)
}

@Test func `host match ignores port`() {
    let config = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["example-corp.com"])],
        defaultBrowserId: chrome,
    )
    #expect(dest("https://example-corp.com:8443/x", config) == island)
}

@Test func `routingConfig JSON round-trips`() throws {
    let config = RoutingConfig(
        browsers: [
            BrowserRule(id: island, patterns: ["example-corp.com", "github.com/example-corp/*"]),
            BrowserRule(id: chrome, patterns: []),
        ],
        defaultBrowserId: chrome,
    )
    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(RoutingConfig.self, from: encoded)
    #expect(decoded == config)
}

@MainActor
@Test func `routingStore add remove and persist`() throws {
    let suite = try #require(UserDefaults(suiteName: UUID().uuidString))
    let store = RoutingStore(defaults: suite)
    store.addBrowser(bundleId: island)
    store.addBrowser(bundleId: island)
    store.addBrowser(bundleId: chrome)
    #expect(store.config.browsers.map(\.id) == [island, chrome])

    store.setDefault(bundleId: chrome)
    store.addPattern("  EXAMPLE.COM ", to: island)
    store.addPattern("example.com", to: island)
    store.addPattern("   ", to: island)
    store.addPattern("github.com/org/*", to: island)
    #expect(store.config.browsers[0].patterns == ["example.com", "github.com/org/*"])

    store.removePattern(at: 0, from: island)
    #expect(store.config.browsers[0].patterns == ["github.com/org/*"])

    let reloaded = RoutingStore(defaults: suite)
    #expect(reloaded.config == store.config)
    #expect(reloaded.config.defaultBrowserId == chrome)

    store.removeBrowser(bundleId: chrome)
    #expect(store.config.defaultBrowserId == nil)
    #expect(store.config.browsers.map(\.id) == [island])
}

@Test func `normalizePattern strips scheme query fragment and slash`() {
    #expect(RoutingStore.normalizePattern("  HTTPS://Example.COM/Path/?q=1#x  ") == "example.com/path")
    #expect(RoutingStore.normalizePattern("https://github.com/org/repo/") == "github.com/org/repo")
    #expect(RoutingStore.normalizePattern("http://*.corp.com") == "*.corp.com")
    #expect(RoutingStore.normalizePattern("example.com") == "example.com")
}

@Test func `unwrap extracts outlook safelinks destination`() {
    let wrapped = url(
        "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fsportradar.atlassian.net%2Fbrowse%2FSE-2981&data=x",
    )
    let inner = CompiledRules.unwrap(wrapped)
    #expect(inner.host == "sportradar.atlassian.net")
    #expect(inner.path == "/browse/SE-2981")
    let plain = url("https://example.com/x")
    #expect(CompiledRules.unwrap(plain) == plain)
    let bad = url("https://eur01.safelinks.protection.outlook.com/?url=javascript:alert(1)")
    #expect(CompiledRules.unwrap(bad) == bad)
}

@Test func `outlook safelinks matches the inner host`() {
    let config = RoutingConfig(
        browsers: [BrowserRule(id: island, patterns: ["sportradar.atlassian.net"])],
        defaultBrowserId: chrome,
    )
    #expect(dest(
        "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fsportradar.atlassian.net%2Fbrowse%2FSE-2981",
        config,
    ) == island)
    #expect(dest(
        "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fnews.ycombinator.com",
        config,
    ) == chrome)
}

@MainActor
@Test func `adding a pattern moves it off the other browser`() throws {
    let suite = try #require(UserDefaults(suiteName: UUID().uuidString))
    let store = RoutingStore(defaults: suite)
    store.addBrowser(bundleId: island)
    store.addBrowser(bundleId: chrome)
    store.addPattern("https://example.com/", to: island)
    #expect(store.config.browsers[0].patterns == ["example.com"])
    store.addPattern("HTTPS://EXAMPLE.COM", to: chrome)
    #expect(store.config.browsers[0].patterns == [])
    #expect(store.config.browsers[1].patterns == ["example.com"])
}

@MainActor
@Test func `routingEnabled persists and defaults on`() throws {
    let suite = try #require(UserDefaults(suiteName: UUID().uuidString))
    let store = RoutingStore(defaults: suite)
    #expect(store.routingEnabled)
    store.setRoutingEnabled(false)
    #expect(store.routingEnabled == false)
    let reloaded = RoutingStore(defaults: suite)
    #expect(reloaded.routingEnabled == false)
}
