import Foundation
import XCTest
@testable import RevenueCat

final class CacheNamespaceTests: XCTestCase {
    private var namespaces: [CacheNamespace] = []
    private let testBundle = "CacheNamespaceTests.\(UUID().uuidString)"
    private let userID = "same-user"
    private let request = URLRequest(url: URL(string: "https://isi.example.com/v1/subscribers/same-user/offerings")!)

    override func tearDown() {
        for namespace in namespaces {
            for store in CacheNamespace.Store.allCases {
                namespace.userDefaults(for: store).removePersistentDomain(forName: namespace.suiteName(for: store))
            }
        }
        super.tearDown()
    }

    func testDeviceDataSurvivesRestartWithoutCrossingApplicationOrEnvironment() throws {
        let scopes = [scope("classic", "staging"), scope("new_goodnotes", "staging"),
                      scope("new_goodnotes", "production")]
        for (index, namespace) in scopes.enumerated() {
            let cache = deviceCache(namespace)
            XCTAssertNil(cache.cachedOfferingsResponseData(appUserID: userID))
            XCTAssertNil(cache.cachedCustomerInfoData(appUserID: userID))
            cache.cache(appUserID: userID)
            cache.cache(customerInfo: Data("customer-\(index)".utf8), appUserID: userID)
            cache.cache(offerings: offerings("offering-\(index)"), appUserID: userID)
            cache.cache(offerings: offerings("stripe-\(index)"), appUserID: userID, includeStripeProducts: true)
        }
        // New cache instances model launching each runtime again, using the same account ID.
        for (index, namespace) in scopes.enumerated() {
            let cache = deviceCache(namespace)
            XCTAssertEqual(cache.cachedAppUserID, userID)
            XCTAssertEqual(cache.cachedCustomerInfoData(appUserID: userID), Data("customer-\(index)".utf8))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            for stripe in [false, true] {
                let data = try XCTUnwrap(cache.cachedOfferingsResponseData(appUserID: userID, includeStripeProducts: stripe))
                let response = try decoder.decode(OfferingsResponse.self, from: data)
                XCTAssertEqual(response.currentOfferingId, "\(stripe ? "stripe" : "offering")-\(index)")
            }
        }
        deviceCache(scopes[1]).clearCaches(oldAppUserID: userID, andSaveWithNewUserID: "new-user")
        XCTAssertNil(deviceCache(scopes[1]).cachedOfferingsResponseData(appUserID: userID))
        XCTAssertNotNil(deviceCache(scopes[0]).cachedOfferingsResponseData(appUserID: userID))
        XCTAssertNotNil(deviceCache(scopes[2]).cachedCustomerInfoData(appUserID: userID))
    }

    func testETagsAnd304BodiesAreIsolatedAndClearOnlyTheirOwnDomain() throws {
        let scopes = [scope("classic", "staging"), scope("new_goodnotes", "staging"),
                      scope("new_goodnotes", "production")]
        for (index, namespace) in scopes.enumerated() {
            let manager = ETagManager(cacheNamespace: namespace)
            XCTAssertEqual(manager.eTagHeader(for: request, withSignatureVerification: false)["X-RevenueCat-ETag"], "")
            storeResponse(manager, body: "body-\(index)", tag: "tag-\(index)")
            deviceCache(namespace).cache(customerInfo: Data("customer".utf8), appUserID: userID)
        }
        for (index, namespace) in scopes.enumerated() {
            let restarted = ETagManager(cacheNamespace: namespace)
            XCTAssertEqual(restarted.eTagHeader(for: request, withSignatureVerification: false)["X-RevenueCat-ETag"],
                           "tag-\(index)")
            let response = restarted.httpResultFromCacheOrBackend(
                with: response(status: .notModified, body: nil, tag: "tag-\(index)"), request: request, retried: false
            )
            XCTAssertEqual(response?.body, Data("body-\(index)".utf8))
        }
        ETagManager(cacheNamespace: scopes[1]).clearCaches()
        XCTAssertEqual(ETagManager(cacheNamespace: scopes[1])
            .eTagHeader(for: request, withSignatureVerification: false)["X-RevenueCat-ETag"], "")
        for index in [0, 2] {
            XCTAssertEqual(ETagManager(cacheNamespace: scopes[index])
                .eTagHeader(for: request, withSignatureVerification: false)["X-RevenueCat-ETag"], "tag-\(index)")
        }
        XCTAssertNotNil(deviceCache(scopes[1]).cachedCustomerInfoData(appUserID: userID))
    }

    func testJWTInvalidationPreservesOtherScopesAndOtherStores() throws {
        let scopes = [scope("classic", "staging"), scope("new_goodnotes", "staging"),
                      scope("new_goodnotes", "production")]
        for (index, namespace) in scopes.enumerated() {
            let manager = JWTManager(cacheNamespace: namespace)
            XCTAssertNil(manager.jwtToken())
            try storeToken(token(index), in: manager)
            storeResponse(ETagManager(cacheNamespace: namespace), body: "body", tag: "tag")
        }
        for (index, namespace) in scopes.enumerated() {
            XCTAssertEqual(JWTManager(cacheNamespace: namespace).jwtToken(), token(index))
        }
        JWTManager(cacheNamespace: scopes[1]).clearCaches()
        XCTAssertNil(JWTManager(cacheNamespace: scopes[1]).jwtToken())
        XCTAssertEqual(JWTManager(cacheNamespace: scopes[0]).jwtToken(), token(0))
        XCTAssertEqual(JWTManager(cacheNamespace: scopes[2]).jwtToken(), token(2))
        XCTAssertEqual(ETagManager(cacheNamespace: scopes[1])
            .eTagHeader(for: request, withSignatureVerification: false)["X-RevenueCat-ETag"], "tag")
    }

    func testLegacyConfigurationRetainsExistingStorageAndCustomDefaults() {
        let configuration = Configuration.builder(withAPIKey: "classic-key").build()
        XCTAssertNil(configuration.cacheNamespace)
        XCTAssertTrue(CacheNamespace.deviceUserDefaults(namespace: nil, custom: nil) === UserDefaults.computeDefault())
        XCTAssertEqual(ETagManager().persistentDomainName, ETagManager.suiteName)
        XCTAssertEqual(JWTManager().persistentDomainName, JWTManager.suiteName)
        let custom = scope("custom", "staging").userDefaults(for: .device)
        let configured = Configuration.builder(withAPIKey: "classic-key").with(userDefaults: custom).build()
        XCTAssertTrue(CacheNamespace.deviceUserDefaults(namespace: configured.cacheNamespace,
                                                       custom: configured.userDefaults) === custom)
    }

    func testBuilderPreservesApplicationAndEnvironmentScope() throws {
        let configuration = Configuration.builder(withProxyAuthenticationHeadersProvider: {
            ["Authorization": "Bearer test-token"]
        })
        .with(cacheNamespace: "new_goodnotes", environment: "https://isi.example.com")
        .build()
        let namespace = try XCTUnwrap(configuration.cacheNamespace)
        let expected = CacheNamespace(application: "new_goodnotes", environment: "https://isi.example.com")
        for store in CacheNamespace.Store.allCases {
            XCTAssertEqual(namespace.suiteName(for: store), expected.suiteName(for: store))
        }
        XCTAssertNil(configuration.userDefaults)
    }

    func testScopeIdentityIsStableAndUnambiguous() {
        let first = scope("new_goodnotes", "https://isi.example.com")
        let again = scope("new_goodnotes", "https://isi.example.com")
        XCTAssertEqual(first.suiteName(for: .device), again.suiteName(for: .device))
        XCTAssertEqual(Set(CacheNamespace.Store.allCases.map { first.suiteName(for: $0) }).count, 3)
        XCTAssertNotEqual(scope("a|b", "c").suiteName(for: .device), scope("a", "b|c").suiteName(for: .device))
        let otherBundle = CacheNamespace(application: "new_goodnotes", environment: "https://isi.example.com",
                                         bundleIdentifier: "another-app")
        XCTAssertNotEqual(first.suiteName(for: .device), otherBundle.suiteName(for: .device))
    }

    private func scope(_ application: String, _ environment: String) -> CacheNamespace {
        let namespace = CacheNamespace(application: application, environment: environment, bundleIdentifier: testBundle)
        namespaces.append(namespace)
        return namespace
    }

    private func deviceCache(_ namespace: CacheNamespace) -> DeviceCache {
        DeviceCache(sandboxEnvironmentDetector: BundleSandboxEnvironmentDetector(),
                    userDefaults: CacheNamespace.deviceUserDefaults(namespace: namespace, custom: nil))
    }

    private func offerings(_ id: String) -> Offerings {
        Offerings(offerings: [:], currentOfferingID: id, placements: nil, targeting: nil,
                  response: .init(currentOfferingId: id, offerings: [], placements: nil, targeting: nil))
    }

    private func response(status: HTTPStatusCode, body: Data?, tag: String) -> VerifiedHTTPResponse<Data?> {
        .init(httpStatusCode: status, responseHeaders: ["X-RevenueCat-ETag": tag], body: body,
              verificationResult: .notRequested, verificationReason: nil)
    }

    private func storeResponse(_ manager: ETagManager, body: String, tag: String) {
        _ = manager.httpResultFromCacheOrBackend(
            with: response(status: .success, body: Data(body.utf8), tag: tag), request: request, retried: false
        )
    }

    private func token(_ index: Int) -> String {
        let payload = Data(#"{"exp":4102444800}"#.utf8).base64EncodedString()
        return "header\(index).\(payload).signature"
    }

    private func storeToken(_ token: String, in manager: JWTManager) throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                                    headerFields: ["Set-Cookie": "isi_token=\(token); Path=/"]))
        manager.store(from: response)
    }
}
