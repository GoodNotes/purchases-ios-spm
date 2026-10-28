import Foundation
import StoreKit
import XCTest
@testable import RevenueCat

final class OfferingPackageSelectionTests: XCTestCase {
    func testRealISIResponsePreservesAndResolvesRepeatedPackageIdentifiers() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "isi-offerings-duplicate-package-identifiers", withExtension: "json"
        ))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OfferingsResponse.self, from: Data(contentsOf: url))
        let products = Dictionary(uniqueKeysWithValues: response.productIdentifiers.map {
            ($0, StoreProduct(sk1Product: SelectionProduct($0)))
        })
        let offerings = try XCTUnwrap(OfferingsFactory().createOfferings(from: products, data: response))
        XCTAssertEqual(offerings.current?.identifier, "new-goodnotes-launch")
        XCTAssertEqual(offerings.all.count, response.offerings.count)
        for source in response.offerings {
            XCTAssertEqual(offerings[source.identifier]?.availablePackages.count, source.packages.count)
            for package in source.packages {
                let selected = try XCTUnwrap(offerings.package(
                    offeringIdentifier: source.identifier, packageIdentifier: package.identifier,
                    productIdentifier: package.platformProductIdentifier, planKey: package.planKey
                ))
                XCTAssertEqual(selected.storeProduct.productIdentifier, package.platformProductIdentifier)
                XCTAssertEqual(selected.planKey, package.planKey)
                XCTAssertEqual(selected.presentedOfferingContext.offeringIdentifier, source.identifier)
            }
        }
    }

    func testMissingOrAmbiguousSelectionsNeverChooseAnArbitraryPackage() {
        let package = makePackage(plan: "pro")
        let offerings = makeOfferings([package, package])
        XCTAssertNil(offerings.package(offeringIdentifier: "offering", packageIdentifier: "shared",
                                      productIdentifier: "product", planKey: "pro"))
        let unique = makeOfferings([package])
        XCTAssertNil(unique.package(offeringIdentifier: "missing", packageIdentifier: "shared",
                                   productIdentifier: "product", planKey: "pro"))
        XCTAssertNil(unique.package(offeringIdentifier: "offering", packageIdentifier: "missing",
                                   productIdentifier: "product", planKey: "pro"))
        XCTAssertNil(unique.package(offeringIdentifier: "offering", packageIdentifier: "shared",
                                   productIdentifier: "missing", planKey: "pro"))
        XCTAssertNil(unique.package(offeringIdentifier: "offering", packageIdentifier: "shared",
                                   productIdentifier: "product", planKey: nil))
    }

    func testPlanKeyDisambiguatesTheSameProductAndNilIsNotAWildcard() {
        let offerings = makeOfferings([makePackage(plan: "pro"), makePackage(plan: "premium"), makePackage(plan: nil)])
        for plan: String? in ["pro", "premium", nil] {
            let selected = offerings.package(offeringIdentifier: "offering", packageIdentifier: "shared",
                                             productIdentifier: "product", planKey: plan)
            XCTAssertNotNil(selected)
            XCTAssertEqual(selected?.planKey, plan)
        }
    }

    func testSelectionPreservesCurrentOfferingTargetingAttribution() throws {
        let offerings = makeOfferings([makePackage(plan: "pro")], targeting: .init(revision: 7, ruleId: "rule"))
        let selected = try XCTUnwrap(offerings.package(
            offeringIdentifier: "offering", packageIdentifier: "shared", productIdentifier: "product", planKey: "pro"
        ))
        XCTAssertEqual(selected.presentedOfferingContext.targetingContext?.revision, 7)
        XCTAssertEqual(selected.presentedOfferingContext.targetingContext?.ruleId, "rule")
    }

    private func makePackage(plan: String?) -> Package {
        Package(identifier: "shared", packageType: .custom,
                storeProduct: StoreProduct(sk1Product: SelectionProduct("product")),
                offeringIdentifier: "offering", planKey: plan)
    }

    private func makeOfferings(_ packages: [Package], targeting: Offerings.Targeting? = nil) -> Offerings {
        Offerings(offerings: ["offering": Offering(identifier: "offering", serverDescription: "Test",
                                                  availablePackages: packages)],
                  currentOfferingID: "offering", placements: nil, targeting: targeting,
                  response: .init(currentOfferingId: "offering", offerings: [], placements: nil, targeting: nil))
    }
}

private final class SelectionProduct: SKProduct, @unchecked Sendable {
    private let id: String
    init(_ id: String) { self.id = id; super.init() }
    override var productIdentifier: String { id }
    override var localizedTitle: String { id }
    override var localizedDescription: String { "Test product" }
    override var price: NSDecimalNumber { 1 }
    override var priceLocale: Locale { Locale(identifier: "en_US") }
}
