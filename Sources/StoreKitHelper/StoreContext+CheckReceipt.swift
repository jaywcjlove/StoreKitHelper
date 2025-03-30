//
//  StoreContext+CheckReceipt.swift
//  StoreKitHelper
//
//  Created by wong on 3/14/25.
//

import Foundation
import StoreKit

extension StoreContext {
    /// 检查收据的存在
    /// 返回当前有效的（未过期的）购买或订阅记录。适用于验证当前活跃的订阅或购买权限。
    func checkReceipt() async -> Bool {
        guard Bundle.main.appStoreReceiptURL != nil else {
            exitWithStatus173()
            return false
        }
        var hasValidTransaction = false
        /// 返回一个包含当前有效的 已购买商品 的交易列表
        let entitlements = await Transaction.currentEntitlements
        for await result in entitlements {
            switch result {
            case let .verified(transaction):
                await self.updatePurchaseTransactions(with: transaction)
                hasValidTransaction = true
            case let .unverified(transaction, error):
                print("Unverified transaction: \(error.localizedDescription ?? "Unknown error")")
            }
        }
        return hasValidTransaction
    }

    // 退出应用并返回状态码 173
    private func exitWithStatus173() {
        exit(173)
    }
}
