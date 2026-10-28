import CryptoKit
import Foundation
import XCTest
@testable import RevenueCat

final class KeylessProxyTests: XCTestCase {
    func testBuilderDoesNotNeedAStaticKey() async throws {
        let config = Configuration.builder(withProxyAuthenticationHeadersProvider: {
            ["Authorization": "Bearer user-token"]
        }).build()
        XCTAssertTrue(config.apiKey.isEmpty)
        let headers = try await config.proxyAuthenticationHeadersProvider?()
        XCTAssertEqual(headers?["Authorization"], "Bearer user-token")
        XCTAssertTrue(HTTPClient.authorizationHeader(withAPIKey: "").isEmpty)
    }

    func testKeylessRequestsRequireProxyAndBearerAndRemoveLegacyCredentials() throws {
        let input = ["Authorization": "Bearer fresh", "Cookie": "classic", "X-GN-Account-ID": "old",
                     "X-ISI-API-KEY": "key", "X-Platform": "iOS", "X-Nonce": "nonce"]
        XCTAssertThrowsError(try HTTPClient.keylessProxyHeaders(input, isProxyRequest: false))
        for authorization in ["", "Bearer", "Basic abc", "Bearer token\nother"] {
            XCTAssertThrowsError(try HTTPClient.keylessProxyHeaders(["Authorization": authorization], isProxyRequest: true))
        }
        XCTAssertEqual(try HTTPClient.keylessProxyHeaders(input, isProxyRequest: true),
                       ["Authorization": "Bearer fresh", "X-Platform": "iOS", "X-Nonce": "nonce"])
    }

    func testKeyedProxyVerifiesWithStaticKeyWhileAuthorizationUsesFreshBearer() async throws {
        let apiKey = "appl_test-public-key"
        let configuration = Configuration.builder(withAPIKey: apiKey)
            .with(proxyAuthenticationHeadersProvider: { ["Authorization": "Bearer user-token"] })
            .build()
        var headers = HTTPClient.authorizationHeader(withAPIKey: configuration.apiKey)
        let proxyHeaders = try await configuration.proxyAuthenticationHeadersProvider?()
        headers.mergeProxyAuthenticationHeaders(try XCTUnwrap(proxyHeaders))
        XCTAssertEqual(headers, ["Authorization": "Bearer user-token"])

        let root = Curve25519.Signing.PrivateKey()
        let intermediate = Curve25519.Signing.PrivateKey()
        var expiration = UInt32(Date().timeIntervalSince1970 / 86400 + 30).littleEndian
        let expirationBytes = withUnsafeBytes(of: &expiration) { Data($0) }
        let intermediateBytes = intermediate.publicKey.rawRepresentation
        let keySignature = try root.signature(for: expirationBytes + intermediateBytes)
        let salt = Data(repeating: 7, count: 16)
        var parameters = Signing.SignatureParameters(path: .getCustomerInfo(appUserID: "user"),
            message: Data("response".utf8), requestHeaders: headers, requestDate: 1234)
        // Construct the server signature independently, with the static key rather than Authorization.
        let payload = salt + Data(apiKey.utf8) + parameters.asData
        let signature = (intermediateBytes + expirationBytes + keySignature + salt +
                         (try intermediate.signature(for: payload))).base64EncodedString()
        let signing = Signing(apiKey: configuration.apiKey)
        XCTAssertNil(signing.verify(signature: signature, with: parameters, publicKey: root.publicKey))
        parameters.requestHeaders = ["Authorization": "Bearer refreshed-user-token"]
        XCTAssertNil(signing.verify(signature: signature, with: parameters, publicKey: root.publicKey))
        XCTAssertNotNil(Signing(apiKey: "wrong-key").verify(
            signature: signature, with: parameters, publicKey: root.publicKey))
        parameters.message = Data("tampered".utf8)
        XCTAssertNotNil(signing.verify(signature: signature, with: parameters, publicKey: root.publicKey))
    }

    func testSignedResponseUsesSentTokenEvenAfterRefreshAndRejectsTampering() throws {
        let root = Curve25519.Signing.PrivateKey()
        let intermediate = Curve25519.Signing.PrivateKey()
        var expiration = UInt32(Date().timeIntervalSince1970 / 86400 + 30).littleEndian
        let expirationBytes = withUnsafeBytes(of: &expiration) { Data($0) }
        let intermediateBytes = intermediate.publicKey.rawRepresentation
        let keySignature = try root.signature(for: expirationBytes + intermediateBytes)
        let salt = Data(repeating: 7, count: 16)
        let parameters = Signing.SignatureParameters(path: .getCustomerInfo(appUserID: "user"),
            message: Data("response".utf8), requestHeaders: ["Authorization": "Bearer sent-token"], requestDate: 1234)
        // Build the server payload independently of the credential-selection code.
        let message = salt + Data("sent-token".utf8) + parameters.asData
        let signature = (intermediateBytes + expirationBytes + keySignature + salt +
                         (try intermediate.signature(for: message))).base64EncodedString()
        let signing = Signing(apiKey: "")
        XCTAssertNil(signing.verify(signature: signature, with: parameters, publicKey: root.publicKey))
        var refreshed = parameters
        refreshed.requestHeaders = ["Authorization": "Bearer refreshed-token"]
        XCTAssertNotNil(signing.verify(signature: signature, with: refreshed, publicKey: root.publicKey))
        var tampered = parameters
        tampered.message = Data("tampered".utf8)
        XCTAssertNotNil(signing.verify(signature: signature, with: tampered, publicKey: root.publicKey))
        XCTAssertNil(signing.verify(signature: signature, with: parameters, publicKey: root.publicKey))
        XCTAssertFalse(parameters.debugDescription.contains("sent-token"))
        // Static-key configurations keep signing with their original key, regardless of proxy headers.
        XCTAssertEqual(parameters.signature(salt: salt, apiKey: "classic-key"),
                       salt + Data("classic-key".utf8) + parameters.asData)
    }
}
