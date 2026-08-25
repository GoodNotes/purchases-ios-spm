// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import struct Foundation.URL

/// Reads optional compiler flags used while developing the fork locally.
var additionalCompilerFlags: [PackageDescription.SwiftSetting] = {
    guard let config = try? String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Local.xcconfig")
    ) else {
        return []
    }

    return config
        .firstMatch(of: #/^SWIFT_ACTIVE_COMPILATION_CONDITIONS *= *(.*)$/#.anchorsMatchLineEndings())?
        .output
        .1
        .split(whereSeparator: \.isWhitespace)
        .filter { !$0.isEmpty && !$0.hasPrefix("$") }
        .map { .define(String($0)) }
        ?? []
}()

var ciCompilerFlags: [PackageDescription.SwiftSetting] = [
    // REPLACE_WITH_DEFINES_HERE
]
// See https://github.com/RevenueCat/purchases-ios/pull/2989
// #if os(visionOS) can't really be used in Xcode 13, so we use this instead.
let visionOSSetting: SwiftSetting = .define("VISION_OS", .when(platforms: [.visionOS]))

let package = Package(
    name: "RevenueCat",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v10_15),
        .watchOS("6.2"),
        .tvOS(.v13),
        .iOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "RevenueCat",
                 targets: ["RevenueCat"])
    ],
    targets: [
        .target(name: "RevenueCat",
                path: "Sources",
                resources: [
                    .copy("../Sources/PrivacyInfo.xcprivacy")
                ],
                swiftSettings: [visionOSSetting]
                    + ciCompilerFlags
                    + additionalCompilerFlags
                    + [.define("ENABLE_TRANSACTION_METADATA")])
    ]
)
