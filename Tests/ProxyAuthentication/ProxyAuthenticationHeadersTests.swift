import XCTest
@testable import RevenueCat

final class ProxyAuthenticationHeadersTests: XCTestCase {
    func testExplicitProxyBearerReplacesAPIKeyCaseInsensitively() {
        var headers = ["authorization": "Bearer public-key", "X-Nonce": "protected"]
        headers.mergeProxyAuthenticationHeaders(["AUTHORIZATION": "Bearer user-token", "x-nonce": "bad"])
        XCTAssertEqual(headers["Authorization"], "Bearer user-token")
        XCTAssertNil(headers["authorization"])
        XCTAssertEqual(headers["X-Nonce"], "protected")
        XCTAssertNil(headers["x-nonce"])
    }
    func testClassicCookiesKeepAPIKeyAndAppendExistingCookies() {
        var headers = ["Authorization": "Bearer public-key", "Cookie": "region=eu"]
        headers.mergeProxyAuthenticationHeaders(["cookie": "session=value"])
        XCTAssertEqual(headers["Authorization"], "Bearer public-key")
        XCTAssertEqual(headers["Cookie"], "region=eu; session=value")
    }
    func testEmptyBearerCannotEraseAuthorization() {
        var headers = ["Authorization": "Bearer public-key"]
        headers.mergeProxyAuthenticationHeaders(["Authorization": ""])
        XCTAssertEqual(headers["Authorization"], "Bearer public-key")
    }
    func testAdditionalPublicKeyHeaderIsRetained() {
        var headers = ["Authorization": "Bearer public-key"]
        headers.mergeProxyAuthenticationHeaders(["Authorization": "Bearer user-token", "Custom-Public-Key": "public-key"])
        XCTAssertEqual(headers["Custom-Public-Key"], "public-key")
    }
}
