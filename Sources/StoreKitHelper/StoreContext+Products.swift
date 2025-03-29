//
//  StoreContext+Products.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//

import StoreKit

public extension StoreContext {
    func isProductPurchased(id: ProductID) -> Bool {
        purchasedProductIds.contains(id)
    }
    func isProductPurchased(_ product: Product) -> Bool {
        isProductPurchased(id: product.id)
    }
    /// - Parameters:
    ///   - id: The ID of the product to fetch.
    func product(withId id: ProductFetchID) -> Product? {
        products.first { $0.id == id }
    }
    func getProducts() async throws -> [Product] {
        /// ⚠️ 苹果缓`存机制`导致，列表获取为`空`
        /// `重现问题:` 如果网络先断掉，启动应用，无法获取应用可购买的产品列表，再打开应用，获取仍然无法获取产品列表，需要重启应用，才能重新获取
        /// 暂时没有找到解决方案，在支付界面提示用户`重启应用`
        return try await Product.products(for: productIds)
    }
    // MARK: - 购买
    /// 购买某个产品
    @discardableResult
    func purchase(_ product: Product) async throws -> (Product.PurchaseResult, Transaction?) {
        let result = try await purchaseResult(product)
        if let transaction = result.1 {
            await updatePurchaseTransactions(with: transaction)
        }
        return result
    }
    @discardableResult
    func purchaseResult(_ product: Product) async throws -> (Product.PurchaseResult, Transaction?) {
        let result = try await product.purchase()
        var transaction: Transaction? = nil
        switch result {
        case .success(let result):
            switch result {
            case .verified(let verifiedTransaction):
                transaction = verifiedTransaction  // 提取已验证的 Transaction
                try await finalizePurchaseResult(result)  // 处理已验证的交易
            case .unverified: break
            }
        case .pending: break
        case .userCancelled: break
        @unknown default: break
        }
        
        return (result, transaction)
    }
    /// Finalize a purchase result from a ``purchaseResult(_:)``.
    /// 购买结果确认
    func finalizePurchaseResult(_ result: VerificationResult<Transaction>) async throws {
        let transaction = try result.verify()
        await transaction.finish()
    }
    
    func getValidProductTransations() async throws -> [Transaction] {
        var transactions: [Transaction] = []
        for id in productIds {
            if let transaction = try await getValidTransaction(for: id) {
                transactions.append(transaction)
            }
        }
        return transactions
    }
    /// 获取某个产品的所有有效交易
    func getValidTransaction(for productId: ProductID) async throws -> Transaction? {
        guard let latest = await Transaction.latest(for: productId) else { return nil }
        let result: Transaction = try latest.verify()
        return result.isValid ? result : nil
    }
    /// 监听事务更新
    /// 这个函数由初始化器调用，用于获取交易更新并尝试验证它们。
    func updateTransactionsOnLaunch() -> Task<Void, Never> {
        return Task.detached(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try result.verify()
                    await self.updatePurchaseTransactions(with: transaction)
                } catch {
                    print("🚨 Transaction listener error: \(error.localizedDescription)")
                }
            }
        }
    }
    /// 更新交易记录
    func updatePurchaseTransactions(with transaction: Transaction) {
        var transactions = purchaseTransactions.filter {
            $0.productID != transaction.productID
        }
        transactions.append(transaction)
        purchaseTransactions = transactions
    }
}

private extension VerificationResult where SignedType == Transaction {
    @discardableResult
    func verify() throws -> Transaction {
        switch self {
        case .unverified(let transaction, let error): throw StoreServiceError.invalidTransaction(transaction, error)
        case .verified(let transaction): return transaction
        }
    }
}
