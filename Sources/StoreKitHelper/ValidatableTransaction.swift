//
//  ValidatableTransaction.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//

import StoreKit

/// 任何可以被验证的交易都可以实现此协议。
///
/// 有效的交易没有撤销日期，并且过期日期尚未过期。
public protocol ValidatableTransaction {
    /// 交易的过期日期（如果有）。
    var expirationDate: Date? { get }
    /// 交易的撤销日期（如果有）。
    var revocationDate: Date? { get }
}

extension Transaction: ValidatableTransaction {}

public extension ValidatableTransaction {
    /// 交易是否有效。
    ///
    /// 有效的交易没有撤销日期，并且没有已过期的过期日期。
    var isValid: Bool {
        if revocationDate != nil { return false }
        guard let date = expirationDate else { return true }
        return date > Date()
    }
}
