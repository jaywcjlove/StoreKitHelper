// The Swift Programming Language
// https://docs.swift.org/swift-book

import StoreKit
//
//extension StoreContext: SKPaymentTransactionObserver {
//    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
//        print("Subscriptions Payment Queue! updated!")
//        for transaction in transactions {
//            switch transaction.transactionState {
//            case .purchased:
//                print("1 交易失败:1")
//                completeTransaction(transaction)
//            case .failed:
//                print("1 交易失败:2")
//                failedTransaction(transaction)
//            case .restored:
//                print("1 交易失败:3")
//                restoreTransaction(transaction)
//            case .deferred, .purchasing:
//                print("1 交易失败:4")
//                break
//            @unknown default:
//                print("1 交易失败:5")
//                break
//            }
//        }
//    }
//    /// 处理成功的交易
//    private func completeTransaction(_ transaction: SKPaymentTransaction) {
//        DispatchQueue.main.async {
//            self.purchasedProductIds.append(transaction.payment.productIdentifier)
//        }
//        SKPaymentQueue.default().finishTransaction(transaction)
//    }
//    /// 处理恢复购买
//    private func restoreTransaction(_ transaction: SKPaymentTransaction) {
//        if let productId = transaction.original?.payment.productIdentifier {
//            DispatchQueue.main.async {
//                self.purchasedProductIds.append(productId)
//            }
//        }
//        SKPaymentQueue.default().finishTransaction(transaction)
//    }
//
//    /// 处理失败的交易
//    private func failedTransaction(_ transaction: SKPaymentTransaction) {
//        if let error = transaction.error as NSError?, error.code != SKError.paymentCancelled.rawValue {
//            print("❌ 交易失败: \(error.localizedDescription)")
//        }
//        SKPaymentQueue.default().finishTransaction(transaction)
//    }
//}

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
    /// 已购买的产品ID
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
//        self._products = Published(initialValue: []) // ✅ 通过 `_products` 进行初始化
        // 调用 NSObject 的初始化方法
//        super.init()
        // 赋值产品 ID（持久化逻辑）
        self.productIds = persistedProductIds.isEmpty || productIds.count != persistedProductIds.count
                    ? productIds : persistedProductIds
        purchasedProductIds = persistedPurchasedProductIds
        transactionUpdateTask = updateTransactionsOnLaunch()
        // 添加 StoreKit 交易监听
//        SKPaymentQueue.default().add(self)
        Task {
            try await syncStoreData()
        }
    }
    deinit {
        // 移除 StoreKit 交易监听
//        SKPaymentQueue.default().remove(self)
        transactionUpdateTask?.cancel()
    }
}

@MainActor public extension StoreContext {
    /// 更新上下文产品
    func updateProducts(_ products: [Product]) {
        self.products = products
    }
    /// 更新交易记录
    func updatePurchaseTransactions(with transaction: Transaction) {
        var transactions = purchaseTransactions.filter { $0.productID != transaction.productID }
        transactions.append(transaction)
        purchaseTransactions = transactions
    }
    /// 更新上下文购买交易
    func updatePurchaseTransactions(_ transactions: [Transaction]) {
        purchaseTransactions = transactions
    }
}

private extension StoreContext {
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
