//
//  StoreContext+Products.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//

import StoreKit

/// 定义的产品 ID 这是`固定`的
public typealias ProductID = String
/// 请求的产品 ID
public typealias ProductFetchID = String
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
    open func getProducts() async throws -> [Product] {
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
    open func purchaseResult(_ product: Product) async throws -> (Product.PurchaseResult, Transaction?) {
        let result = try await product.purchase()
        switch result {
        case .success(let result): try await finalizePurchaseResult(result)
        case .pending: break
        case .userCancelled: break
        @unknown default: break
        }
        return (result, nil)
    }
    /// Finalize a purchase result from a ``purchaseResult(_:)``.
    /// 购买结果确认
    open func finalizePurchaseResult(_ result: VerificationResult<Transaction>) async throws {
        let transaction = try result.verify()
        await transaction.finish()
    }
    // MARK: - 恢复购买
    /// 恢复购买
    func restorePurchases() async throws {
        let transactions = try await getValidProductTransations()
        await updatePurchaseTransactions(transactions)
    }
    
    open func getValidProductTransations() async throws -> [Transaction] {
        var transactions: [Transaction] = []
        for id in productIds {
            if let transaction = try await getValidTransaction(for: id) {
                transactions.append(transaction)
            }
        }
        return transactions
    }
    /// 获取某个产品的所有有效交易
    open func getValidTransaction(for productId: ProductID) async throws -> Transaction? {
        guard let latest = await Transaction.latest(for: productId) else { return nil }
        let result = try latest.verify()
        return result.isValid ? result : nil
    }
    /// 这个函数由初始化器调用，用于获取交易更新并尝试验证它们。
    open func updateTransactionsOnLaunch() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    try result.verify()
                } catch {
                    print("Transaction listener error: \(error.localizedDescription)")
                }
            }
        }
    }
    /// 同步存储数据
    open func syncStoreData() async throws {
        let products = try await getProducts()
        await updateProducts(products)
        try await restorePurchases()
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
