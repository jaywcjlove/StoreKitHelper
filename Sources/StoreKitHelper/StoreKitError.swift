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
             (.purchasePending, .purchasePending):
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
            return String.localizedString(key: "product_load_failed", locale: locale, error.localizedDescription)
        case .purchaseFailed(let error):
            return String.localizedString(key: "purchase_failed_with_error", locale: locale, error.localizedDescription)
        case .restoreFailed(let error):
            return String.localizedString(key: "restore_failed_with_error", locale: locale, error.localizedDescription)
        case .verificationFailed:
            return String.localizedString(key: "verification_failed", locale: locale)
        case .networkError(let error):
            return String.localizedString(key: "network_error", locale: locale, error.localizedDescription)
        case .userCancelled:
            return String.localizedString(key: "user_cancelled", locale: locale)
        case .purchasePending:
            return String.localizedString(key: "purchase_pending", locale: locale)
        case .unknownError(let message):
            return String.localizedString(key: "unknown_error", locale: locale)
        }
    }
}
