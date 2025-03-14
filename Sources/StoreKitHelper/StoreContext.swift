// The Swift Programming Language
// https://docs.swift.org/swift-book

import StoreKit

public class StoreContext: ObservableObject, @unchecked Sendable {
    /// 更新
    private var transactionUpdateTask: Task<Void, Never>? = nil
    /**
    已同步的产品列表。

    您可以使用此属性来跟踪从 StoreKit 获取的产品集合。

    由于 `Product` 不是 `Codable`，此属性无法持久化， 必须在应用启动时重新加载。
     */
    @Persisted(key: key("productIds"), defaultValue: [])
    private var persistedProductIds: [String]
    /// 产品列表 ID
    @Published public internal(set) var productIds: [String] = [] {
        willSet { persistedProductIds = newValue }
    }
    /// 产品列表 -  更新 ``StoreContext/productIds`` ID，通过 ``StoreContext/updateProducts(_:)`` 更新产品列表
    @Published public var products: [Product] = [] {
        didSet { productIds = products.map { $0.id} }
    }
    /**
    购买的产品 ID 列表。

    您可以使用此属性来跟踪从 StoreKit 获取的已购买产品。

    此属性是持久化的，这意味着当 StoreKit 请求失败时，
    您可以将这些 ID 映射到本地的产品表示。
     */
    @Persisted(key: key("purchasedProductIds"), defaultValue: []) private var persistedPurchasedProductIds: [String]
    /// 已购买的产品ID，限制 id 只能在模块中修改
    @Published public internal(set) var purchasedProductIds: [String] = [] {
        willSet { persistedPurchasedProductIds = newValue }
    }
    /// 购买交易，同时`更新`已购买的产品 ``StoreContext/purchasedProductIds`` ID
    public var purchaseTransactions: [Transaction] = [] {
        didSet { purchasedProductIds = purchaseTransactions.map { $0.productID } }
    }
    
    /// 弹出 PopUp 显示产品支付界面
    /// 是否显示购买弹窗
    @Published public var isShowingPurchasePopup: Bool = false
    /// ``StoreContext/init(productIds:)``
    public convenience init<Product: InAppProduct>(products: [Product]) {
        self.init(productIds: products.map { $0.id })
    }
    public init(productIds: [ProductID] = []) {
        // 赋值产品 ID（持久化逻辑）
        self.productIds = persistedProductIds.isEmpty || productIds.count != persistedProductIds.count
                    ? productIds : persistedProductIds
        purchasedProductIds = persistedPurchasedProductIds
        transactionUpdateTask = updateTransactionsOnLaunch()
        Task {
            await self.checkReceipt()
            try await syncStoreData()
        }
    }
    deinit {
        transactionUpdateTask?.cancel()
    }
}

@MainActor public extension StoreContext {
    // MARK: - 恢复购买
    /// 恢复购买
    func restorePurchases() async throws {
        // 同步应用内购买信息
        try await AppStore.sync()
        try await updatePurchases()
    }
    /// 同步存储数据
    func syncStoreData() async throws {
        let products = try await getProducts()
        await updateProducts(products)
        /// 更新购买信息
        try await updatePurchases()
    }
    /// 更新购买信息
    func updatePurchases() async throws {
        let transactions = try await getValidProductTransations()
        await updatePurchaseTransactions(transactions)
    }
    /// 更新上下文产品
    func updateProducts(_ products: [Product]) {
        self.products = products
    }
    /// 更新交易记录
    func updatePurchaseTransactions(with transaction: Transaction) {
        var transactions = purchaseTransactions.filter {
            $0.productID != transaction.productID
        }
        transactions.append(transaction)
        purchaseTransactions = transactions
    }
    /// 更新上下文购买交易
    func updatePurchaseTransactions(_ transactions: [Transaction]) {
        purchaseTransactions = transactions
    }
}

extension StoreContext {
    static func key(_ name: String) -> String { "com.wangchujiang.storekithelp.\(name)" }
}

/// This property wrapper automatically persists a new value to user defaults.
@propertyWrapper struct Persisted<T: Codable> {
    init(key: String, store: UserDefaults = .standard, defaultValue: T) {
        self.key = key
        self.store = store
        self.defaultValue = defaultValue
    }
    private let key: String
    private let store: UserDefaults
    private let defaultValue: T
    var wrappedValue: T {
        get {
            guard let data = store.object(forKey: key) as? Data else { return defaultValue }
            let value = try? JSONDecoder().decode(T.self, from: data)
            return value ?? defaultValue
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            store.set(data, forKey: key)
        }
    }
}
