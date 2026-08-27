import Foundation
#if canImport(Sparkle)
    import Sparkle
#endif

/// Abstracts auto-update so dev/unsigned/Homebrew builds can use a no-op and tests
/// can inject a fake.
@MainActor
protocol UpdaterProviding {
    var canCheckForUpdates: Bool { get }
    func start()
    func checkForUpdates()
}

@MainActor
enum AppServices {
    static var updater: any UpdaterProviding = DisabledUpdater()
}

/// No-op updater for dev builds, unsigned bundles, and Homebrew-cask installs
/// (Homebrew manages its own updates).
@MainActor
final class DisabledUpdater: UpdaterProviding {
    var canCheckForUpdates: Bool {
        false
    }

    func start() {}
    func checkForUpdates() {}
}

@MainActor
func makeUpdater() -> any UpdaterProviding {
    #if canImport(Sparkle)
        if SparkleUpdater.shouldEnable {
            return SparkleUpdater()
        }
    #endif
    return DisabledUpdater()
}

#if canImport(Sparkle)
    @MainActor
    final class SparkleUpdater: NSObject, UpdaterProviding {
        private let controller: SPUStandardUpdaterController

        /// Only enable Sparkle for a real .app bundle that is not a Homebrew cask,
        /// AND only once a real EdDSA public key is baked into Info.plist. Without a
        /// key (dev/unsigned builds) the appcast is unsigned/missing, so auto-checks
        /// just throw a "failed to update" alert — keep the no-op updater instead.
        /// (For production, also verify a Developer ID signature before enabling.)
        static var shouldEnable: Bool {
            let path = Bundle.main.bundlePath
            guard path.hasSuffix(".app"), !path.contains("/Caskroom/") else { return false }
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
            return !key.isEmpty && !key.hasPrefix("REPLACE_")
        }

        override init() {
            controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil,
            )
            super.init()
        }

        var canCheckForUpdates: Bool {
            true
        }

        func start() {
            controller.startUpdater()
        }

        func checkForUpdates() {
            controller.updater.checkForUpdates()
        }
    }
#endif
