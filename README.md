# RevenueCat SDK fork for Goodnotes

This repository contains the minimal RevenueCat SDK surface used by Goodnotes' In-App Subscription Infrastructure (ISI).
It is based on RevenueCat 5.16.3 and is distributed only as a Swift package.

## Package contents

The package exposes one library product and one target, both named `RevenueCat`. It intentionally excludes upstream
products and features that Goodnotes does not use, including:

- RevenueCatUI and the paywall editor runtime
- Customer Center
- Standalone receipt parsing
- Custom entitlement computation
- Upstream examples, test applications, and release tooling

The core customer-info paywall metadata used by GNISI remains part of the fork. This is separate from RevenueCatUI and
is required to decode the ISI server response.

## Integration

Add the package and depend only on the `RevenueCat` product:

```swift
.package(
    url: "https://github.com/GoodNotes/purchases-ios-spm.git",
    exact: "<goodnotes-version>"
)
```

```swift
.product(name: "RevenueCat", package: "purchases-ios-spm")
```

## Requirements

- Xcode 15 or later
- iOS 13 or later
- tvOS 13 or later
- macOS 10.15 or later
- watchOS 6.2 or later
- visionOS 1 or later

## Validation

Build the package with:

```shell
swift build -c release --target RevenueCat
```

The upstream history is retained for traceability. Removing files from the current tree reduces checkout size and
shallow-clone downloads, but does not reduce the object database of a full clone that includes the complete history.

## Goodnotes keyless authenticated proxy

NGN uses Good Systems access tokens without a RevenueCat public API key:

```swift
Purchases.proxyURL = isiOrigin
let configuration = Configuration.builder(withProxyAuthenticationHeadersProvider: {
    ["Authorization": "Bearer \(try await session.freshAccessToken())"]
})
.with(appUserID: goodSystemsSubject)
.build()
Purchases.configure(with: configuration)
```

The provider runs for each request and must throw when the session is unavailable.
A missing proxy or bearer fails before network I/O. This mode excludes Classic
cookies, `x-gn-account-id` and `X-ISI-API-KEY`, and never falls back to a static
credential. Response verification uses the bearer captured in the sent request,
not the current session token. Token-bearing diagnostic data is redacted.
The existing API-key builder, including Classic's cookie provider, keeps its
existing behavior. Do not put a rotating access token into `withAPIKey`.

The signed-message format remains RevenueCat's format with the request bearer
in place of the static API key. Local cryptographic tests cover token rotation
and tampering; live ISI interoperability must also be verified by the integrator.


### Keeping a static signature credential with bearer authentication

The RC API key is also part of the response-signature payload, not just an
Authorization credential. The existing keyed builder already supports keeping
that key locally while the proxy provider sends a Good Systems bearer instead:

```swift
let configuration = Configuration.builder(withAPIKey: publicAPIKey)
    .with(proxyAuthenticationHeadersProvider: {
        ["Authorization": "Bearer \(try await session.freshAccessToken())"]
    })
    .with(appUserID: goodSystemsSubject)
    .build()
```

With a trusted `Purchases.proxyURL` configured, `Authorization` contains the user
token, while response verification still uses `publicAPIKey`. ISI must sign with
that same static key. A separate header carrying the key is not added automatically;
only provide one if the server contract requires it. This mode and keyless mode
use different signature credentials and must match the server's implementation.
Token refresh does not change the keyed signature credential. Classic's keyed
builder with cookie authentication keeps its existing behavior.

### Resolving serialized package selections

ISI may return the same package identifier for multiple StoreKit products or plans
within an offering. Hybrid bridges should serialize the full selection and let
the SDK resolve it, rather than build a dictionary keyed by package identifier:

```swift
let offerings = try await Purchases.shared.offerings()
guard let package = offerings.package(
    offeringIdentifier: offeringID,
    packageIdentifier: packageID,
    productIdentifier: productID,
    planKey: planKey
) else {
    // Ask the caller to reload: the selection is missing or ambiguous.
    return
}
let result = try await Purchases.shared.purchase(package: package)
```

The lookup requires exactly one match, preserves current-offering targeting
attribution, and treats a nil plan key as an exact match, not a wildcard. Existing
`Offering.package(identifier:)` behavior remains unchanged for existing clients.
