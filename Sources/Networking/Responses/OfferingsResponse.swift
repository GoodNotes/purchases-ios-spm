//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  OfferingsResponse.swift
//
//  Created by Nacho Soto on 3/31/22.

import Foundation

struct OfferingsResponse {

    struct Offering {

        // swiftlint:disable:next nesting
        struct Package {

            let identifier: String
            let platformProductIdentifier: String
            let planKey: String?
            var platform: String? = nil

            var isAppStoreProduct: Bool {
                self.platform == nil || self.platform?.lowercased() == "ios"
            }

        }

        let identifier: String
        let description: String
        let packages: [Package]
        @DefaultDecodable.EmptyDictionary
        var metadata: [String: AnyDecodable]

    }

    struct Placements {
        let fallbackOfferingId: String?
        @DefaultDecodable.EmptyDictionary
        var offeringIdsByPlacement: [String: String?]
    }

    struct Targeting {
        let revision: Int
        let ruleId: String
    }

    let currentOfferingId: String?
    let offerings: [Offering]
    let placements: Placements?
    let targeting: Targeting?

}

extension OfferingsResponse {

    var productIdentifiers: Set<String> {
        return Set(
            self.offerings
                .lazy
                .flatMap { $0.packages }
                .filter { $0.isAppStoreProduct }
                .map { $0.platformProductIdentifier }
        )
    }

}

extension OfferingsResponse.Offering.Package: Codable, Equatable {}
extension OfferingsResponse.Offering: Codable, Equatable {}
extension OfferingsResponse.Placements: Codable, Equatable {}
extension OfferingsResponse.Targeting: Codable, Equatable {}
extension OfferingsResponse: Codable, Equatable {}

extension OfferingsResponse: HTTPResponseBody {}

extension OfferingsResponse.Offering {

    /// Pairs products only within this offering. Ambiguous matches are not purchasable through Stripe.
    func stripeProductIdentifier(for package: Package) -> String? {
        let identifiers = Set(self.packages.filter {
            $0.platform?.lowercased() == "stripe" && $0.identifier == package.identifier &&
                ($0.planKey == nil || package.planKey == nil || $0.planKey == package.planKey)
        }.map { $0.platformProductIdentifier }.filter { !$0.isEmpty })
        return identifiers.count == 1 ? identifiers.first : nil
    }

}
