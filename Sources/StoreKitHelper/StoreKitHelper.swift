import Foundation
import StoreKit
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - InAppProduct Protocol

/// 定义的产品 ID 这是`固定`的
public typealias ProductID = String

/// 协议，用于定义应用内购买产品
public protocol InAppProduct: CaseIterable, Identifiable where ID == ProductID {
    /// 产品标识符
    var id: ProductID { get }
}

/// 购买状态
public enum PurchaseStatus: Sendable, Equatable {
    /// 当前购买状态尚未完成首次同步
    case loading
    /// 当前存在有效购买
    case purchased
    /// 当前不存在有效购买
    case notPurchased
}

/// 单个商品在本地交易缓存里的结论。
enum EntitlementLookup: Equatable {
    /// 有当前仍有效的交易
    case entitled
    /// 交易存在，但已退款、过期或被升级替换
    case notEntitled
    /// 有交易，验签未通过
    case unverified
    /// 本地缓存里还没有这笔交易
    case missing
}

/// 权益刷新的来源。自动刷新遇到空缓存时保留本进程已确认的购买；恢复购买以本次同步为准。
enum EntitlementRefreshMode: Equatable {
    case automatic
    case restore
}

struct EntitlementSnapshot: Equatable {
    var scannedIDs: Set<String> = []
    var lookups: [String: EntitlementLookup] = [:]
    var sawUnverified = false
}

struct EntitlementMergeResult: Equatable {
    var productIDs: Set<String>
    var reportUnverified: Bool
}

/// 把 `currentEntitlements` 和按商品补查的结果合成一份购买集合。
/// 第二台 Mac 的 `currentEntitlements` 经常先是空的；补查到有效交易时要算已购买。
/// 自动刷新如果只是“缓存还没这条记录”，不能清掉本进程里刚验过的购买。
func mergeEntitlements(
    snapshot: EntitlementSnapshot,
    existingIDs: Set<String>,
    sessionGrantsToKeep: Set<String>,
    mode: EntitlementRefreshMode
) -> EntitlementMergeResult {
    var productIDs = snapshot.scannedIDs
    var sawUnverified = snapshot.sawUnverified

    for (productID, lookup) in snapshot.lookups {
        switch lookup {
        case .entitled:
            productIDs.insert(productID)
        case .notEntitled:
            productIDs.remove(productID)
        case .unverified:
            sawUnverified = true
        case .missing:
            break
        }
    }

    let protectedIDs: Set<String>
    switch mode {
    case .automatic:
        protectedIDs = existingIDs
    case .restore:
        protectedIDs = sessionGrantsToKeep
    }

    for productID in protectedIDs where productIDs.contains(productID) == false {
        switch snapshot.lookups[productID] {
        case .notEntitled:
            break
        case .unverified:
            sawUnverified = true
            productIDs.insert(productID)
        case .entitled, .missing, nil:
            productIDs.insert(productID)
        }
    }

    return EntitlementMergeResult(
        productIDs: productIDs,
        reportUnverified: sawUnverified && productIDs.isEmpty
    )
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
    /// 当前购买状态
    @Published public private(set) var purchaseStatus: PurchaseStatus = .loading
    /// 是否正在加载
    @Published public private(set) var isLoading = false
    /// 错误信息
    @Published public private(set) var storeError: StoreKitError?
    /// 弹出 PopUp 显示产品支付界面
    /// 是否显示购买弹窗
    @Published public var isShowingPurchasePopup: Bool = false
    /// 是否显示优惠代码兑换面板
    @Published public var isShowingOfferCodeRedemption: Bool = false
    
    // MARK: - Computed Properties
    
    /// 用户是否没有购买任何产品
    public var hasNotPurchased: Bool {
        purchaseStatus == .notPurchased
    }
    
    /// 用户是否已购买任何产品
    public var hasPurchased: Bool {
        purchaseStatus == .purchased
    }
    
    /// 用户购买状态是否已完成首次同步
    public var hasResolvedPurchaseStatus: Bool {
        purchaseStatus != .loading
    }
    public let productIDs: [String]
    
    // MARK: - Private Properties
    
    private var transactionListener: Task<Void, Never>?
    private var entitlementRefreshTail: Task<Void, Never>?
    private var entitlementRetryTask: Task<Void, Never>?
    private var entitlementRefreshGeneration: UInt64 = 0
    private var activationObserver: NSObjectProtocol?
    private var lastEntitlementRefreshAt: Date?
    /// 本进程里验签通过的商品。恢复购买时只保护同步期间新出现的那些，避免空缓存把它们清掉。
    private var verifiedThisSession: Set<String> = []
    /// 优惠码兑换页还开着时先记下，等页面关闭再解锁，避免付费墙在系统弹窗底下被收起。
    private var pendingOfferProductIDs: Set<String> = []
    private var shouldRefreshPurchasedProductsAfterOfferCodeRedemption = false
    
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
        observeApplicationActivation()
        isLoading = true
        // 加载产品和当前购买状态
        Task {
            await updatePurchasedProducts()
            await loadProducts()
            if purchasedProductIDs.isEmpty {
                scheduleEntitlementRetriesIfUnpurchased()
            }
        }
    }
    
    isolated deinit {
        transactionListener?.cancel()
        entitlementRetryTask?.cancel()
        entitlementRefreshTail?.cancel()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }
    
    // MARK: 购买产品
    /// - Parameter product: 要购买的产品
    public func purchase(_ product: Product, options: Set<Product.PurchaseOption> = []) async {
        cancelEntitlementRetries()
        do {
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verificationResult):
                guard let transaction = checkVerified(verificationResult) else {
                    storeError = .verificationFailed
                    return
                }
                if await isTransactionEntitled(transaction) {
                    grantVerifiedPurchase(transaction.productID)
                    storeError = nil
                } else {
                    revokeVerifiedPurchase(transaction.productID)
                }
                await transaction.finish()
                await updatePurchasedProducts()
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
        cancelEntitlementRetries()
        isLoading = true
        storeError = nil
        let grantsBeforeSync = verifiedThisSession
        
        do {
            // 同步 App Store 状态。同步刚返回时，currentEntitlements 仍可能是空的。
            try await AppStore.sync()
            await refreshAfterRestore(grantsBeforeSync: grantsBeforeSync)
            if purchasedProductIDs.isEmpty {
                try? await Task.sleep(for: .milliseconds(800))
                await refreshAfterRestore(grantsBeforeSync: grantsBeforeSync)
            }
            isLoading = false
        } catch {
            isLoading = false
            if isStoreKitCancellation(error) {
                storeError = .userCancelled
            } else {
                storeError = .restoreFailed(error)
            }
        }
    }
    
    /// 清除当前错误
    public func clearError() {
        storeError = nil
    }

    /// 显示优惠代码兑换面板
    public func presentOfferCodeRedemption() {
        isShowingOfferCodeRedemption = true
    }

    /// 更新优惠代码兑换面板显示状态
    func setOfferCodeRedemptionPresented(_ isPresented: Bool) {
        isShowingOfferCodeRedemption = isPresented
        guard isPresented == false,
              shouldRefreshPurchasedProductsAfterOfferCodeRedemption == true else {
            return
        }

        Task {
            await refreshPurchasedProductsAfterOfferCodeRedemption()
        }
    }

    /// 重新同步当前有效购买
    public func refreshPurchasedProducts() async {
        await updatePurchasedProducts()
    }

    /// 处理优惠代码兑换面板的完成结果
    public func handleOfferCodeRedemption(_ result: Result<Void, Error>) async {
        switch result {
        case .success:
            storeError = nil
            if isShowingOfferCodeRedemption == true {
                shouldRefreshPurchasedProductsAfterOfferCodeRedemption = true
            } else {
                await updatePurchasedProducts()
            }
        case .failure(let error):
            storeError = .purchaseFailed(error)
        }
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
        guard let transaction = checkVerified(verificationResult) else {
            if purchasedProductIDs.isEmpty {
                storeError = .verificationFailed
            }
            return
        }

        let entitled = await isTransactionEntitled(transaction)
        guard isShowingOfferCodeRedemption == false else {
            if entitled {
                verifiedThisSession.insert(transaction.productID)
                pendingOfferProductIDs.insert(transaction.productID)
            } else {
                revokeVerifiedPurchase(transaction.productID)
            }
            shouldRefreshPurchasedProductsAfterOfferCodeRedemption = true
            await transaction.finish()
            return
        }

        if entitled {
            grantVerifiedPurchase(transaction.productID)
            storeError = nil
        } else {
            revokeVerifiedPurchase(transaction.productID)
        }
        await transaction.finish()
        await updatePurchasedProducts()
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

    private func refreshPurchasedProductsAfterOfferCodeRedemption() async {
        shouldRefreshPurchasedProductsAfterOfferCodeRedemption = false
        let pendingProductIDs = pendingOfferProductIDs
        pendingOfferProductIDs = []
        for productID in pendingProductIDs {
            grantVerifiedPurchase(productID)
        }
        await updatePurchasedProducts()
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
                // 商品列表加载成功只表示目录可用，不能清掉验签失败。
                if case .verificationFailed = self.storeError {
                    return
                }
                self.storeError = nil
            }
        } catch {
            await MainActor.run {
                self.storeError = .productLoadFailed(error)
                self.isLoading = false
            }
        }
    }
    
    /// 更新已购买的产品。后发起的刷新会使更早的扫描作废，避免空结果盖掉新购买。
    private func updatePurchasedProducts() async {
        await enqueueEntitlementRefresh(mode: .automatic, sessionGrantsToKeep: [])
    }

    private func refreshAfterRestore(grantsBeforeSync: Set<String>) async {
        let grantsDuringSync = verifiedThisSession.subtracting(grantsBeforeSync)
        await enqueueEntitlementRefresh(mode: .restore, sessionGrantsToKeep: grantsDuringSync)
    }

    private func enqueueEntitlementRefresh(
        mode: EntitlementRefreshMode,
        sessionGrantsToKeep: Set<String>
    ) async {
        entitlementRefreshGeneration &+= 1
        let generation = entitlementRefreshGeneration
        let previous = entitlementRefreshTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, Task.isCancelled == false else { return }
            guard generation == self.entitlementRefreshGeneration else { return }
            await self.performEntitlementRefresh(
                mode: mode,
                sessionGrantsToKeep: sessionGrantsToKeep,
                generation: generation
            )
        }
        entitlementRefreshTail = task
        await task.value
    }

    private func performEntitlementRefresh(
        mode: EntitlementRefreshMode,
        sessionGrantsToKeep: Set<String>,
        generation: UInt64
    ) async {
        guard generation == entitlementRefreshGeneration else { return }
        var snapshot = await collectEntitlementSnapshot()
        guard generation == entitlementRefreshGeneration else { return }

        let candidates = Set(productIDs)
            .union(purchasedProductIDs)
            .union(sessionGrantsToKeep)
            .subtracting(snapshot.scannedIDs)
        for productID in candidates {
            snapshot.lookups[productID] = await lookupEntitlement(productID)
            guard generation == entitlementRefreshGeneration else { return }
        }
        // 兑换页还在时，先不要把刚兑换的商品写进已购买，等页面关闭再解锁。
        if isShowingOfferCodeRedemption {
            snapshot.scannedIDs.subtract(pendingOfferProductIDs)
            for productID in pendingOfferProductIDs {
                snapshot.lookups[productID] = .missing
            }
        }

        let merged = mergeEntitlements(
            snapshot: snapshot,
            existingIDs: purchasedProductIDs,
            sessionGrantsToKeep: sessionGrantsToKeep,
            mode: mode
        )
        guard generation == entitlementRefreshGeneration else { return }

        purchasedProductIDs = merged.productIDs
        purchaseStatus = merged.productIDs.isEmpty ? .notPurchased : .purchased
        lastEntitlementRefreshAt = Date()
        if merged.reportUnverified {
            storeError = .verificationFailed
        } else if merged.productIDs.isEmpty == false, case .verificationFailed = storeError {
            storeError = nil
        }
    }

    /// `currentEntitlements` 只反映当前这笔读取时的本地缓存。
    private func collectEntitlementSnapshot() async -> EntitlementSnapshot {
        var snapshot = EntitlementSnapshot()
        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            switch verificationResult {
            case .verified(let transaction):
                if await isTransactionEntitled(transaction) {
                    snapshot.scannedIDs.insert(transaction.productID)
                }
            case .unverified:
                snapshot.sawUnverified = true
            }
        }
        return snapshot
    }

    /// 按商品补查。`currentEntitlements` 为空时，非消耗型购买仍可能在 `Transaction.latest` 里。
    private func lookupEntitlement(_ productID: String) async -> EntitlementLookup {
        guard let verificationResult = await StoreKit.Transaction.latest(for: productID) else {
            return .missing
        }
        guard let transaction = checkVerified(verificationResult) else {
            return .unverified
        }
        if await isTransactionEntitled(transaction) {
            return .entitled
        }
        return .notEntitled
    }

    /// `currentEntitlements` 会包含宽限期内的订阅，那些交易的 `expirationDate` 可能已经早于本机时间。
    private func isTransactionEntitled(_ transaction: StoreKit.Transaction) async -> Bool {
        guard transaction.revocationDate == nil, transaction.isUpgraded == false else {
            return false
        }
        if let status = await transaction.subscriptionStatus {
            let state = status.state
            if state == .subscribed || state == .inGracePeriod {
                return true
            }
            if state == .expired || state == .revoked || state == .inBillingRetryPeriod {
                return false
            }
        }
        if let expirationDate = transaction.expirationDate {
            return expirationDate > Date()
        }
        return true
    }

    private func grantVerifiedPurchase(_ productID: String) {
        verifiedThisSession.insert(productID)
        purchasedProductIDs.insert(productID)
        purchaseStatus = .purchased
        entitlementRefreshGeneration &+= 1
        if case .verificationFailed = storeError {
            storeError = nil
        }
    }

    private func revokeVerifiedPurchase(_ productID: String) {
        verifiedThisSession.remove(productID)
        pendingOfferProductIDs.remove(productID)
        purchasedProductIDs.remove(productID)
        if purchasedProductIDs.isEmpty, purchaseStatus != .loading {
            purchaseStatus = .notPurchased
        }
        // 让已经读完、还没写回的扫描失效，避免它把刚撤销的商品又写回来。
        entitlementRefreshGeneration &+= 1
    }

    private func scheduleEntitlementRetriesIfUnpurchased() {
        entitlementRetryTask?.cancel()
        entitlementRetryTask = Task { [weak self] in
            for delay in [Duration.seconds(2), .seconds(6), .seconds(15)] {
                try? await Task.sleep(for: delay)
                guard Task.isCancelled == false else { return }
                await self?.retryEntitlementRefreshIfStillUnpurchased()
            }
        }
    }

    private func retryEntitlementRefreshIfStillUnpurchased() async {
        guard purchaseStatus == .notPurchased else { return }
        await updatePurchasedProducts()
    }

    private func cancelEntitlementRetries() {
        entitlementRetryTask?.cancel()
        entitlementRetryTask = nil
    }

    private func observeApplicationActivation() {
        #if os(macOS)
        let name = NSApplication.didBecomeActiveNotification
        #elseif os(watchOS)
        let name = WKApplication.didBecomeActiveNotification
        #else
        let name = UIApplication.didBecomeActiveNotification
        #endif
        activationObserver = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAfterActivation()
            }
        }
    }

    private func refreshAfterActivation() async {
        if let lastEntitlementRefreshAt, Date().timeIntervalSince(lastEntitlementRefreshAt) < 1 {
            return
        }
        await updatePurchasedProducts()
    }

    private func isStoreKitCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let storeKitError = error as? StoreKit.StoreKitError, case .userCancelled = storeKitError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == SKError.errorDomain
            && nsError.code == SKError.Code.paymentCancelled.rawValue
    }
}

#if DEBUG
extension StoreContext {
    func _setPurchasedProductIDsForTesting(_ productIDs: Set<String>) {
        purchasedProductIDs = productIDs
        purchaseStatus = productIDs.isEmpty ? .notPurchased : .purchased
    }
    
    func _setPurchaseStatusForTesting(_ status: PurchaseStatus) {
        purchaseStatus = status
        if status != .purchased {
            purchasedProductIDs = []
        }
    }
}
#endif
