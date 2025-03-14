//
//  StoreContext+CheckReceipt.swift
//  StoreKitHelper
//
//  Created by wong on 3/14/25.
//

import Foundation
import StoreKit

extension StoreContext {
    // 检查收据的存在
    func checkReceipt() async {
        guard Bundle.main.appStoreReceiptURL != nil else {
            exitWithStatus173()
            return
        }
        var hasValidTransaction = false
        for await transaction in Transaction.all {
            if case .verified(let transaction) = transaction {
                await self.updatePurchaseTransactions(with: transaction)
                hasValidTransaction = true
                break
            }
        }
        if !hasValidTransaction {
            // 没有找到任何有效的交易，处理这种情况
            // print("No valid transactions found.")
            // 你可以在这里添加处理逻辑，例如显示提示或退出应用
        }
    }

    // 退出应用并返回状态码 173
    private func exitWithStatus173() {
        exit(173)
    }
}
