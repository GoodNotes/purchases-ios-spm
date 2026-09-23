//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  GetOfferingsOperation.swift
//
//  Created by Joshua Liebowitz on 11/19/21.

import Foundation

final class GetOfferingsOperation: CacheableNetworkOperation {

    private let offeringsCallbackCache: CallbackCache<OfferingsCallback>
    private let configuration: AppUserConfiguration
    private let includeStripeProducts: Bool

    static func createFactory(
        configuration: UserSpecificConfiguration,
        offeringsCallbackCache: CallbackCache<OfferingsCallback>,
        includeStripeProducts: Bool = false
    ) -> CacheableNetworkOperationFactory<GetOfferingsOperation> {
        return .init({ cacheKey in
                    .init(
                        configuration: configuration,
                        offeringsCallbackCache: offeringsCallbackCache,
                        cacheKey: cacheKey,
                        includeStripeProducts: includeStripeProducts
                    )
            },
            individualizedCacheKeyPart: configuration.appUserID + (includeStripeProducts ? ":ios,stripe" : ""))
    }

    private init(configuration: UserSpecificConfiguration,
                 offeringsCallbackCache: CallbackCache<OfferingsCallback>,
                 cacheKey: String,
                 includeStripeProducts: Bool) {
        self.configuration = configuration
        self.includeStripeProducts = includeStripeProducts
        self.offeringsCallbackCache = offeringsCallbackCache

        super.init(configuration: configuration, cacheKey: cacheKey)
    }

    override func begin(completion: @escaping () -> Void) {
        self.getOfferings(completion: completion)
    }

}

// Restating inherited @unchecked Sendable from Foundation's Operation
extension GetOfferingsOperation: @unchecked Sendable {}

private extension GetOfferingsOperation {

    func getOfferings(completion: @escaping () -> Void) {
        let appUserID = self.configuration.appUserID

        guard appUserID.isNotEmpty else {
            self.offeringsCallbackCache.performOnAllItemsAndRemoveFromCache(withCacheable: self) { callback in
                callback.completion(.failure(.missingAppUserID()))
            }
            completion()

            return
        }

        var request = HTTPRequest(method: .get, path: .getOfferings(appUserID: appUserID))
        if self.includeStripeProducts {
            request.additionalHeaders = ["x-app-type": "ios", "x-supported-platforms": "ios,stripe"]
        }

        httpClient.perform(request) { (response: VerifiedHTTPResponse<OfferingsResponse>.Result) in
            defer {
                completion()
            }

            self.offeringsCallbackCache.performOnAllItemsAndRemoveFromCache(withCacheable: self) { callbackObject in
                callbackObject.completion(response
                    .map { $0.body }
                    .mapError(BackendError.networkError)
                )
            }
        }
    }

}
