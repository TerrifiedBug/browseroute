import Foundation
import Security
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

        /// Sparkle only for a Developer ID-signed `.app` that is not a Homebrew cask,
        /// with a real EdDSA public key in Info.plist. Ad-hoc `make install` builds
        /// share that plist, so the signature check is what keeps them on the no-op
        /// updater — otherwise they would auto-replace themselves with the notarized zip.
        static var shouldEnable: Bool {
            let path = Bundle.main.bundlePath
            guard path.hasSuffix(".app"), !path.contains("/Caskroom/") else { return false }
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
            guard !key.isEmpty, !key.hasPrefix("REPLACE_") else { return false }
            return isDeveloperIDSigned(at: Bundle.main.bundleURL)
        }

        /// Team 92X3ACDPD2 Developer ID Application. Ad-hoc, Apple Development,
        /// and other-team signatures do not match. Skip sealed-resource hashing:
        /// the requirement still evaluates the cert chain, and a cold-start URL
        /// open should not wait on Sparkle.framework's CodeResources.
        static let developerIDRequirement =
            "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and "
                + "certificate leaf[field.1.2.840.113635.100.6.1.13] exists and "
                + "certificate leaf[subject.OU] = \"92X3ACDPD2\""

        static func isDeveloperIDSigned(at url: URL) -> Bool {
            var staticCode: SecStaticCode?
            let created = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
            guard created == errSecSuccess, let staticCode else { return false }

            var requirement: SecRequirement?
            let parsed = SecRequirementCreateWithString(
                developerIDRequirement as CFString,
                [],
                &requirement,
            )
            guard parsed == errSecSuccess, let requirement else { return false }
            return SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSDoNotValidateResources),
                requirement,
            ) == errSecSuccess
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
