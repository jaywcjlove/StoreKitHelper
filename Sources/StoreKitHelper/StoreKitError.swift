//
//  StoreKitError.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import Foundation

/// StoreKit 错误类型
public enum StoreKitError: Error, LocalizedError, Equatable {
    case productLoadFailed(Error)
    case purchaseFailed(Error)
    case restoreFailed(Error)
    case verificationFailed
    case networkError(Error)
    case userCancelled
    case purchasePending
    case unknownError(String)
    /// 席位总数不在 1...100。
    case invalidSeatCount
    /// 购买会减少已经买下的席位。减少席位要到订阅设置里操作。
    case seatReductionNotAllowed
    /// 当前系统不能发起团购，或者这个 SDK 还没有 `Product.PurchaseOption.seats(_:)`。
    case multiSeatPurchaseUnavailable
    
    // 扩展 Equatable 协议，定义具体比较
    public static func ==(lhs: StoreKitError, rhs: StoreKitError) -> Bool {
        switch (lhs, rhs) {
        case (.productLoadFailed(let lhsError), .productLoadFailed(let rhsError)),
             (.purchaseFailed(let lhsError), .purchaseFailed(let rhsError)),
             (.networkError(let lhsError), .networkError(let rhsError)):
            // 比较内部的 Error 类型（可以根据需要实现具体的比较逻辑）
            return (lhsError as NSError).isEqual(rhsError as NSError)
            
        case (.verificationFailed, .verificationFailed),
             (.userCancelled, .userCancelled),
             (.purchasePending, .purchasePending),
             (.invalidSeatCount, .invalidSeatCount),
             (.seatReductionNotAllowed, .seatReductionNotAllowed),
             (.multiSeatPurchaseUnavailable, .multiSeatPurchaseUnavailable):
            return true
            
        case (.unknownError(let lhsMessage), .unknownError(let rhsMessage)):
            return lhsMessage == rhsMessage
            
        default:
            return false
        }
    }
    
    public func description(locale: Locale) -> String {
        switch self {
        case .productLoadFailed(let error):
            return StoreKitHelperL18n.localized(key: "product_load_failed", locale: locale, error.localizedDescription)
        case .purchaseFailed(let error):
            return StoreKitHelperL18n.localized(key: "purchase_failed_with_error", locale: locale, error.localizedDescription)
        case .restoreFailed(let error):
            return StoreKitHelperL18n.localized(key: "restore_failed_with_error", locale: locale, error.localizedDescription)
        case .verificationFailed:
            return StoreKitHelperL18n.localized(key: "verification_failed", locale: locale)
        case .networkError(let error):
            return StoreKitHelperL18n.localized(key: "network_error", locale: locale, error.localizedDescription)
        case .userCancelled:
            return StoreKitHelperL18n.localized(key: "user_cancelled", locale: locale)
        case .purchasePending:
            return StoreKitHelperL18n.localized(key: "purchase_pending", locale: locale)
        case .unknownError(_):
            return StoreKitHelperL18n.localized(key: "unknown_error", locale: locale)
        case .invalidSeatCount:
            return StoreKitHelperL18n.localized(
                key: "invalid_seat_count",
                locale: locale,
                MultiSeatPurchase.maximumSeatCount
            )
        case .seatReductionNotAllowed:
            return StoreKitHelperL18n.localized(key: "seat_reduction_not_allowed", locale: locale)
        case .multiSeatPurchaseUnavailable:
            return StoreKitHelperL18n.localized(key: "multi_seat_purchase_unavailable", locale: locale)
        }
    }
}
