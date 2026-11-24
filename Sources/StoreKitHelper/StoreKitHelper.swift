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

/// 权益刷新的来源。两种模式都只在 StoreKit 明确否认时移除购买。
/// 缓存里还没有记录时，保留本进程已经确认过的购买。
enum EntitlementRefreshMode: Equatable {
    case automatic
    case restore
}

struct EntitlementProbe {
    var lookup: EntitlementLookup
    var seatFact: SeatTransactionFact?
    var sawVerifiedTransaction = false
}

struct EntitlementSnapshot: Equatable {
    var scannedIDs: Set<String> = []
    var lookups: [String: EntitlementLookup] = [:]
    var sawUnverified = false
    var seatFacts: [SeatTransactionFact] = []
    /// 这次扫描读到过交易的产品。空缓存不能据此清掉上一份席位记录。
    var productsSeenInEntitlements: Set<String> = []
}

struct EntitlementMergeResult: Equatable {
    var productIDs: Set<String>
    var reportUnverified: Bool
}

/// 本地曾经出现过这笔交易，后来 `Transaction.latest` 又变成空，说明记录已经被清掉。
/// 启动时缓存还没同步则不是这种情况，应继续等待。
func entitlementLookupForMissingTransaction(wasSeenInCache: Bool) -> EntitlementLookup {
    wasSeenInCache ? .notEntitled : .missing
}

/// 把 `currentEntitlements` 和按商品补查的结果合成一份购买集合。
/// 第二台 Mac 的 `currentEntitlements` 经常先是空的；补查到有效交易时要算已购买。
/// 缓存只是还没有记录时，不能清掉本进程里刚验过的购买。
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
        protectedIDs = existingIDs.union(sessionGrantsToKeep)
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
    /// 多名额订阅的席位。键是产品 ID。
    /// 团购购买者、Apple 托管邀请的成员，以及机构分配到席位的人都会出现在这里。
    /// 开发者托管邀请的成员没有 App Store 交易，不在这里。
    @Published public private(set) var multiSeatGrants: [ProductID: MultiSeatGrant] = [:]
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
    /// 本进程里验签通过的商品。同步期间新出现的交易即使缓存还没跟上，也不能被恢复购买清掉。
    private var verifiedThisSession: Set<String> = []
    /// 本地缓存里曾经出现过交易记录的商品。之后再读不到，就视为已退出账号或记录被移除。
    private var productsSeenInCache: Set<String> = []
    /// 优惠码兑换页还开着时先记下，等页面关闭再解锁，避免付费墙在系统弹窗底下被收起。
    private var pendingOfferProductIDs: Set<String> = []
    /// 本进程刚验过、权益扫描可能还没读到的多名额交易。
    private var sessionSeatFacts: [SeatTransactionFact] = []
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
        defer { resumeEntitlementRetriesIfNeeded() }
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
                    await rememberSeatFact(from: transaction)
                    storeError = nil
                } else {
                    forgetSeatFact(transactionID: transaction.id)
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

    /// 购买多名额订阅，或给已经买下的团购加席。
    ///
    /// `seats` 是购买完成后的席位总数，不是这次要增加的数量。例如已有 8 席再加 4 席，传 12。
    /// 单次最多 100 席。比现有席位更少会失败，减少席位要到订阅设置里操作。
    /// 团购可以在 iPhone、iPad 和 Mac 上购买。邀请成员和机构分配到的席位，在每台设备上都会进当前权益。
    public func purchase(
        _ product: Product,
        seats targetSeatQuantity: Int,
        suppressInvitationSheet: Bool = false,
        options: Set<Product.PurchaseOption> = []
    ) async {
        let purchaserActiveSeats = purchaserSeatCount(for: product.id)
        switch validateMultiSeatPurchase(
            targetSeatQuantity: targetSeatQuantity,
            purchaserActiveSeats: purchaserActiveSeats
        ) {
        case .invalidSeatCount:
            storeError = .invalidSeatCount
            return
        case .seatReductionNotAllowed:
            storeError = .seatReductionNotAllowed
            return
        case .valid:
            break
        }
        #if os(iOS) || os(macOS)
        guard let seatOptions = resolvedMultiSeatPurchaseOptions(
            seats: targetSeatQuantity,
            suppressInvitationSheet: suppressInvitationSheet
        ) else {
            storeError = .multiSeatPurchaseUnavailable
            return
        }
        var purchaseOptions = options
        purchaseOptions.formUnion(seatOptions)
        await purchase(product, options: purchaseOptions)
        #else
        storeError = .multiSeatPurchaseUnavailable
        #endif
    }

    /// 打开系统订阅管理页。减少席位，以及当前系统还不能展示邀请面板时的邀请，都从这里走。
    @discardableResult
    public func presentMultiSeatManagement() -> Bool {
        let url = MultiSeatPurchase.subscriptionSettingsURL
        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #elseif os(watchOS)
        return false
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        return true
        #else
        return false
        #endif
    }

    /// 这个产品当前还有效的席位数。没有多名额交易时返回 nil。
    public func activeSeatCount(for productID: ProductID) -> Int? {
        multiSeatGrants[productID]?.activeSeatCount
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
        // 缓存可能在同步返回之后才写完。这次没读到购买时，继续做启动时那几轮补查。
        resumeEntitlementRetriesIfNeeded()
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
        transactionListener = Task.detached { [weak self] in
            for await verificationResult in StoreKit.Transaction.updates {
                await self?.handleTransaction(verificationResult)
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
                await rememberSeatFact(from: transaction)
            } else {
                forgetSeatFact(transactionID: transaction.id)
                revokeVerifiedPurchase(transaction.productID)
            }
            shouldRefreshPurchasedProductsAfterOfferCodeRedemption = true
            await transaction.finish()
            return
        }

        if entitled {
            grantVerifiedPurchase(transaction.productID)
            await rememberSeatFact(from: transaction)
            storeError = nil
        } else {
            forgetSeatFact(transactionID: transaction.id)
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
            let probe = await lookupEntitlement(productID)
            snapshot.lookups[productID] = probe.lookup
            if probe.sawVerifiedTransaction {
                snapshot.productsSeenInEntitlements.insert(productID)
            }
            if let fact = probe.seatFact {
                snapshot.seatFacts.append(fact)
            }
            guard generation == entitlementRefreshGeneration else { return }
        }
        var grantsToKeep = sessionGrantsToKeep
        // 兑换页还在时，先不要把刚兑换的商品写进已购买，等页面关闭再解锁。
        if isShowingOfferCodeRedemption {
            snapshot.scannedIDs.subtract(pendingOfferProductIDs)
            snapshot.productsSeenInEntitlements.subtract(pendingOfferProductIDs)
            snapshot.seatFacts.removeAll { pendingOfferProductIDs.contains($0.productID) }
            grantsToKeep.subtract(pendingOfferProductIDs)
            for productID in pendingOfferProductIDs {
                snapshot.lookups[productID] = .missing
            }
        }

        let merged = mergeEntitlements(
            snapshot: snapshot,
            existingIDs: purchasedProductIDs,
            sessionGrantsToKeep: grantsToKeep,
            mode: mode
        )
        guard generation == entitlementRefreshGeneration else { return }

        purchasedProductIDs = merged.productIDs
        purchaseStatus = merged.productIDs.isEmpty ? .notPurchased : .purchased
        applySeatRefresh(snapshot: snapshot, purchasedProductIDs: merged.productIDs)
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
                productsSeenInCache.insert(transaction.productID)
                snapshot.productsSeenInEntitlements.insert(transaction.productID)
                if await isTransactionEntitled(transaction) {
                    snapshot.scannedIDs.insert(transaction.productID)
                    if let fact = await seatFact(from: transaction) {
                        snapshot.seatFacts.append(fact)
                    }
                }
            case .unverified:
                snapshot.sawUnverified = true
            }
        }
        return snapshot
    }

    /// 按商品补查。`currentEntitlements` 为空时，非消耗型购买仍可能在 `Transaction.latest` 里。
    private func lookupEntitlement(_ productID: String) async -> EntitlementProbe {
        guard let verificationResult = await StoreKit.Transaction.latest(for: productID) else {
            return EntitlementProbe(
                lookup: entitlementLookupForMissingTransaction(
                    wasSeenInCache: productsSeenInCache.contains(productID)
                )
            )
        }
        guard let transaction = checkVerified(verificationResult) else {
            return EntitlementProbe(lookup: .unverified)
        }
        productsSeenInCache.insert(productID)
        if await isTransactionEntitled(transaction) {
            return EntitlementProbe(
                lookup: .entitled,
                seatFact: await seatFact(from: transaction),
                sawVerifiedTransaction: true
            )
        }
        return EntitlementProbe(lookup: .notEntitled, sawVerifiedTransaction: true)
    }

    /// `currentEntitlements` 会包含宽限期内的订阅，那些交易的 `expirationDate` 可能已经早于本机时间。
    /// 消耗型商品没有持续权益，买过一次也不能一直留在已购买集合里。
    private func isTransactionEntitled(_ transaction: StoreKit.Transaction) async -> Bool {
        guard transaction.productType != .consumable else {
            return false
        }
        guard transaction.revocationDate == nil, transaction.isUpgraded == false else {
            return false
        }
        // 成员被移出团购，或机构收回席位时，撤销类型是 assignmentRevocation。
        if #available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) {
            if transaction.revocationType == .assignmentRevocation {
                return false
            }
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

    private func purchaserSeatCount(for productID: String) -> Int? {
        guard let grant = multiSeatGrants[productID] else { return nil }
        switch grant.ownership {
        case .purchased, .unknown:
            return grant.activeSeatCount
        case .assigned, .familyShared:
            return nil
        }
    }

    private func applySeatRefresh(snapshot: EntitlementSnapshot, purchasedProductIDs: Set<String>) {
        let suppressed = isShowingOfferCodeRedemption ? pendingOfferProductIDs : []
        let heldBack = sessionSeatFacts.filter { suppressed.contains($0.productID) }
        let output = mergeMultiSeatGrants(MultiSeatRefreshInput(
            scannedFacts: snapshot.seatFacts,
            sessionFacts: sessionSeatFacts.filter { suppressed.contains($0.productID) == false },
            purchasedProductIDs: purchasedProductIDs,
            productsSeenInEntitlements: snapshot.productsSeenInEntitlements,
            previousGrants: multiSeatGrants
        ))
        multiSeatGrants = output.grants
        sessionSeatFacts = output.sessionFacts + heldBack
    }

    private func rememberSeatFact(from transaction: StoreKit.Transaction) async {
        guard let fact = await seatFact(from: transaction) else { return }
        sessionSeatFacts.removeAll { $0.transactionID == fact.transactionID }
        sessionSeatFacts.append(fact)
    }

    private func forgetSeatFact(transactionID: UInt64) {
        sessionSeatFacts.removeAll { $0.transactionID == transactionID }
    }

    private func seatFact(from transaction: StoreKit.Transaction) async -> SeatTransactionFact? {
        guard transaction.productType != .consumable else { return nil }
        var renewalSeatCount: Int?
        if let status = await transaction.subscriptionStatus,
           case .verified(let renewalInfo) = status.renewalInfo {
            renewalSeatCount = parseRenewalSeatCount(from: renewalInfo.jsonRepresentation)
        }
        return makeSeatTransactionFact(
            transactionID: transaction.id,
            productID: transaction.productID,
            purchasedQuantity: transaction.purchasedQuantity,
            originalID: transaction.originalID,
            ownership: multiSeatOwnership(for: transaction.ownershipType),
            jsonRepresentation: transaction.jsonRepresentation,
            renewalSeatCount: renewalSeatCount
        )
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

    private func resumeEntitlementRetriesIfNeeded() {
        guard purchaseStatus == .notPurchased else { return }
        scheduleEntitlementRetriesIfUnpurchased()
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
