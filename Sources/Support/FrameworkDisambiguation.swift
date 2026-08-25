//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  FrameworkDisambiguation.swift
//
//  Created by Nacho Soto on 4/25/23.w

/**
 Purpose: several parts of the SDK need to explicitly reference a type or value whose Objective-C name already uses
 the `RC` prefix. These aliases keep those references unambiguous without qualifying them through the module name.
 */

typealias RCRefundRequestStatus = RefundRequestStatus
typealias RCErrorCode = ErrorCode
typealias RCOffering = Offering
typealias RCStorefront = Storefront

let RCDefaultLogHandler = defaultLogHandler
