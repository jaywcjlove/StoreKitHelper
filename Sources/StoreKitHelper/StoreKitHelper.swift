import Foundation
import SwiftUI
import StoreKit

// MARK: - InAppProduct Protocol

/// 定义的产品 ID 这是`固定`的
public typealias ProductID = String

/// 协议，用于定义应用内购买产品
public protocol InAppProduct: CaseIterable, Identifiable where ID == ProductID {
    /// 产品标识符
    var id: ProductID { get }
}

// MARK: - StoreContext

/// StoreKit 上下文，用于管理应用内购买状态
@MainActor
public final class StoreContext: ObservableObject {
    // MARK: - Published Properties
    /// 产品列表
    @Published public private(set) var products: [Product] = []
    /// 购买的产品标识符集合
    @Published public private(set) var purchasedProductIDs: Set<String> = []
    /// 是否正在加载
    @Published public private(set) var isLoading = false
    /// 错误信息
    @Published public private(set) var storeError: StoreKitError?
    /// 弹出 PopUp 显示产品支付界面
    /// 是否显示购买弹窗
    @Published public var isShowingPurchasePopup: Bool = false
    
    // MARK: - Computed Properties
    
    /// 用户是否没有购买任何产品
    public var hasNotPurchased: Bool {
        purchasedProductIDs.isEmpty
    }
    
    /// 用户是否已购买任何产品
    public var hasPurchased: Bool {
        !purchasedProductIDs.isEmpty
    }
    public let productIDs: [String]
    
    // MARK: - Private Properties
    
    private var transactionListener: Task<Void, Never>?
    
    // MARK: - Initialization
    /// 初始化 StoreContext
    /// - Parameter products: 产品列表
    /// ``StoreContext/init(productIds:)``
    public convenience init<T: InAppProduct>(products: [T]) {
        self.init(productIds: products.map { $0.id })
    }
    /// 初始化 StoreContext
    /// - Parameter productIds: 产品 ID 列表
    public init(productIds: [ProductID] = []) {
        self.productIDs = productIds
        // 开始监听交易更新
        startTransactionListener()
        isLoading = true
        // 加载产品和当前购买状态
        Task {
            await updatePurchasedProducts()
            await loadProducts()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: 购买产品
    /// - Parameter product: 要购买的产品
    public func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verificationResult):
                if let transaction = checkVerified(verificationResult) {
                    // 更新购买状态
                    purchasedProductIDs.insert(transaction.productID)
                    // 完成交易
                    await transaction.finish()
                    
                    storeError = nil
                } else {
                    storeError = .verificationFailed
                }
            case .userCancelled:
                storeError = .userCancelled
            case .pending:
                storeError = .purchasePending
            @unknown default:
                storeError = .unknownError("Unknown purchase result")
            }
        } catch {
            storeError = .purchaseFailed(error)
        }
    }
    
    // MARK: 恢复购买
    public func restorePurchases() async {
        isLoading = true
        storeError = nil
        
        do {
            // 同步 App Store 状态
            try await AppStore.sync()
            // 更新购买状态
            await updatePurchasedProducts()
            
            // 清除错误信息
            await MainActor.run {
                self.isLoading = false
                self.storeError = nil
            }
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.storeError = .restoreFailed(error)
            }
        }
    }
    
    /// 清除当前错误
    public func clearError() {
        storeError = nil
    }
    
    /// 检查是否购买了指定产品
    /// - Parameter productID: 产品标识符
    /// - Returns: 是否已购买
    public func isPurchased(_ productID: ProductID) -> Bool {
        purchasedProductIDs.contains(productID)
    }
    
    /// 检查是否购买了指定产品
    /// - Parameter product: 产品
    /// - Returns: 是否已购买
    public func isPurchased<T: InAppProduct>(_ product: T) -> Bool {
        purchasedProductIDs.contains(product.id)
    }
    
    /// 根据产品ID查找产品
    /// - Parameter productID: 产品标识符
    /// - Returns: 产品对象
    public func product(for productID: ProductID) -> Product? {
        products.first { $0.id == productID }
    }
    
    /// 根据产品查找Product对象
    /// - Parameter product: 产品
    /// - Returns: Product对象
    public func product<T: InAppProduct>(for product: T) -> Product? {
        products.first { $0.id == product.id }
    }
    
    /// 根据传递进来的 `ID` 进行排序
    public func productsSorted() -> [Product] {
        products.sorted {
            if let index1 = productIDs.firstIndex(of: $0.id),
               let index2 = productIDs.firstIndex(of: $1.id) {
                return index1 < index2
            }
            return false
        }
    }
    
    // MARK: - Private Methods
    /// 开始监听交易更新
    private func startTransactionListener() {
        transactionListener = Task.detached {
            for await verificationResult in StoreKit.Transaction.updates {
                await self.handleTransaction(verificationResult)
            }
        }
    }
    
    /// 处理交易
    /// - Parameter verificationResult: 交易验证结果
    private func handleTransaction(_ verificationResult: VerificationResult<StoreKit.Transaction>) async {
        if let transaction = checkVerified(verificationResult) {
            // 更新购买状态
            purchasedProductIDs.insert(transaction.productID)
            // 完成交易
            await transaction.finish()
        }
    }
    
    // MARK: 验证交易
    /// - Parameter result: 验证结果
    /// - Returns: 验证通过的交易
    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified:
            return nil
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: 加载产品列表
    /// 加载产品列表
    private func loadProducts() async {
        isLoading = true
        do {
            let storeProducts = try await Product.products(for: productIDs)
            await MainActor.run {
                self.products = storeProducts.sorted { $0.price < $1.price }
                self.isLoading = false
                self.storeError = nil
            }
        } catch {
            await MainActor.run {
                self.storeError = .productLoadFailed(error)
                self.isLoading = false
            }
        }
    }
    
    /// 更新已购买的产品
    private func updatePurchasedProducts() async {
        var purchasedIDs: Set<String> = []
        /// `currentEntitlements` 会在本地缓存
        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            if let transaction = checkVerified(verificationResult),
               transaction.revocationDate == nil {
                // 检查订阅是否过期
                if let expirationDate = transaction.expirationDate {
                    // 对于订阅产品，检查是否还未过期
                    if expirationDate > Date() {
                        purchasedIDs.insert(transaction.productID)
                    }
                } else {
                    // 对于非订阅产品（如一次性购买），没有过期日期
                    purchasedIDs.insert(transaction.productID)
                }
            }
        }
        
        await MainActor.run {
            self.purchasedProductIDs = purchasedIDs
        }
    }
}

