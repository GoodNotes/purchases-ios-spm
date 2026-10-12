import Foundation
import Testing

@testable import RevenueCat

struct OfferingsRequestHeadersTests {
    private let defaultHeaders: HTTPClient.RequestHeaders = [
        "X-Platform": "iOS",
        "X-Client-Version": "7.0.99",
        "Cookie": "ory_kratos_session=session"
    ]

    @Test
    func stripeOfferingsRequestAsksForStripePlatform() {
        let headers = GetOfferingsOperation.additionalHeaders(includeStripeProducts: true)

        #expect(headers == [
            "x-app-type": "ios",
            "x-platform": "stripe",
            "x-supported-platforms": "ios,stripe"
        ])
    }

    @Test
    func appStoreOfferingsRequestAddsNoHeaders() {
        #expect(GetOfferingsOperation.additionalHeaders(includeStripeProducts: false).isEmpty)
    }

    @Test
    func stripeOfferingsRequestReplacesDefaultPlatform() {
        var headers = defaultHeaders
        headers.applyRequestScopedHTTPHeaders(GetOfferingsOperation.additionalHeaders(includeStripeProducts: true))

        #expect(platformValues(in: headers) == ["stripe"])
        #expect(headers["x-supported-platforms"] == "ios,stripe")
        #expect(headers["X-Client-Version"] == "7.0.99")
        #expect(headers["Cookie"] == "ory_kratos_session=session")
    }

    @Test
    func requestsWithoutScopedHeadersKeepDefaultPlatform() {
        var headers = defaultHeaders
        headers.applyRequestScopedHTTPHeaders(GetOfferingsOperation.additionalHeaders(includeStripeProducts: false))

        #expect(headers == defaultHeaders)
    }

    @Test
    func requestScopedCookiesAreAppended() {
        var headers = defaultHeaders
        headers.applyRequestScopedHTTPHeaders(["cookie": "gnc_accounts_jwt=jwt"])

        #expect(headers["Cookie"] == "ory_kratos_session=session; gnc_accounts_jwt=jwt")
        #expect(headers.keys.filter { $0.caseInsensitiveCompare("Cookie") == .orderedSame }.count == 1)
    }

    @Test
    func sharedHeadersStillDoNotReplaceDefaults() {
        var headers = defaultHeaders
        headers.mergeAdditionalHTTPHeaders(["x-platform": "stripe"])

        #expect(platformValues(in: headers) == ["iOS"])
    }

    private func platformValues(in headers: HTTPClient.RequestHeaders) -> [String] {
        headers.filter { $0.key.caseInsensitiveCompare("X-Platform") == .orderedSame }.map(\.value)
    }
}
