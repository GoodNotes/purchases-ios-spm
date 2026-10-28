import CryptoKit
import Foundation

/// Stable storage identity shared by every persistent cache in one SDK configuration.
/// Separate domains allow HTTP/JWT invalidation without deleting device data or another application's caches.
struct CacheNamespace {
    enum Store: String, CaseIterable {
        case device
        case etags
        case jwt
    }

    private let identifier: String

    init(application: String, environment: String, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        precondition(!application.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     "Cache namespace must not be empty.")
        precondition(!environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     "Cache environment must not be empty.")
        // JSON preserves component boundaries; hashing avoids unsafe suite-name characters and raw endpoints on disk.
        let components = [bundleIdentifier ?? "", application, environment]
        let data = try! JSONEncoder().encode(components)
        self.identifier = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func suiteName(for store: Store) -> String {
        "com.revenuecat.scoped.v1.\(self.identifier).\(store.rawValue)"
    }

    func userDefaults(for store: Store) -> UserDefaults {
        // The fixed prefix and hex digest cannot equal the main bundle ID or NSGlobalDomain.
        UserDefaults(suiteName: self.suiteName(for: store))!
    }

    static func deviceUserDefaults(namespace: CacheNamespace?, custom: UserDefaults?) -> UserDefaults {
        namespace?.userDefaults(for: .device) ?? custom ?? UserDefaults.computeDefault()
    }
}
