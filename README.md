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
