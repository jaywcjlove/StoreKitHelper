import Testing
import StoreKit
import StoreKitTest

@testable import StoreKitHelper

// 测试用的产品枚举
enum TestProduct: String, InAppProduct {
    case basic = "test.basic"
    case premium = "test.premium"
    var id: String { rawValue }
}

@Test("InAppProduct protocol conformance")
func testInAppProductProtocol() async throws {
    // 测试产品枚举是否正确实现了 InAppProduct 协议
    let products = TestProduct.allCases
    
    #expect(products.count == 2)
    #expect(products.contains(.basic))
    #expect(products.contains(.premium))
    
    #expect(TestProduct.basic.id == "test.basic")
    #expect(TestProduct.premium.id == "test.premium")
}

@Test("StoreContext initialization") 
func testStoreContextInitialization() async throws {
    let store = await StoreContext(products: TestProduct.allCases)
    
    // 测试初始状态
    await MainActor.run {
        #expect(store.products.isEmpty) // 初始时产品列表为空（需要从 App Store 加载）
        #expect(store.purchasedProductIDs.isEmpty)
        #expect(store.purchaseStatus == .loading)
        #expect(store.hasResolvedPurchaseStatus == false)
        #expect(store.hasNotPurchased == false)
        #expect(store.hasPurchased == false)
    }
}

@Test("Purchase status check methods") 
func testPurchaseStatusMethods() async throws {
    let store = await StoreContext(products: TestProduct.allCases)
    
    await MainActor.run {
        // 测试购买状态检查方法
        #expect(store.purchaseStatus == .loading)
        #expect(store.isPurchased("test.basic") == false)
        #expect(store.isPurchased(TestProduct.premium) == false)
        store._setPurchaseStatusForTesting(.notPurchased)
        #expect(store.purchaseStatus == .notPurchased)
        #expect(store.hasResolvedPurchaseStatus == true)
        #expect(store.hasNotPurchased == true)
        #expect(store.hasPurchased == false)
        // 模拟购买状态（仅在测试中使用）
        store._setPurchasedProductIDsForTesting(["test.basic"])
        #expect(store.isPurchased("test.basic") == true)
        #expect(store.isPurchased(TestProduct.basic) == true)
        #expect(store.isPurchased("test.premium") == false)
        #expect(store.purchaseStatus == .purchased)
        #expect(store.hasPurchased == true)
        #expect(store.hasNotPurchased == false)
    }
}

@Test("Empty currentEntitlements still unlocks when latest transaction is entitled")
func testMergeKeepsEntitlementMissingFromCurrentEntitlements() {
    let merged = mergeEntitlements(
        snapshot: EntitlementSnapshot(
            scannedIDs: [],
            lookups: ["pro": .entitled]
        ),
        existingIDs: [],
        sessionGrantsToKeep: [],
        mode: .automatic
    )
    #expect(merged.productIDs == ["pro"])
    #expect(merged.reportUnverified == false)
}

@Test("Automatic refresh keeps a purchase when the local cache has no record yet")
func testMergeKeepsExistingPurchaseWhenCacheMisses() {
    let merged = mergeEntitlements(
        snapshot: EntitlementSnapshot(
            scannedIDs: [],
            lookups: ["pro": .missing]
        ),
        existingIDs: ["pro"],
        sessionGrantsToKeep: [],
        mode: .automatic
    )
    #expect(merged.productIDs == ["pro"])
}

@Test("Automatic refresh drops a purchase StoreKit confirms is gone")
func testMergeDropsConfirmedRevocation() {
    let merged = mergeEntitlements(
        snapshot: EntitlementSnapshot(
            scannedIDs: [],
            lookups: ["pro": .notEntitled]
        ),
        existingIDs: ["pro"],
        sessionGrantsToKeep: ["pro"],
        mode: .automatic
    )
    #expect(merged.productIDs.isEmpty)
}

@Test("Restore keeps a purchase when the cache has no record yet")
func testMergeRestoreKeepsPurchaseWhenCacheMisses() {
    let kept = mergeEntitlements(
        snapshot: EntitlementSnapshot(
            scannedIDs: [],
            lookups: ["pro": .missing]
        ),
        existingIDs: ["pro"],
        sessionGrantsToKeep: [],
        mode: .restore
    )
    #expect(kept.productIDs == ["pro"])

    let grantedDuringSync = mergeEntitlements(
        snapshot: EntitlementSnapshot(
            scannedIDs: [],
            lookups: ["pro": .missing]
        ),
        existingIDs: [],
        sessionGrantsToKeep: ["pro"],
        mode: .restore
    )
    #expect(grantedDuringSync.productIDs == ["pro"])
}

@Test("A transaction that disappeared from the cache is no longer entitled")
func testMissingTransactionAfterBeingSeenIsNotEntitled() {
    #expect(entitlementLookupForMissingTransaction(wasSeenInCache: true) == .notEntitled)
    #expect(entitlementLookupForMissingTransaction(wasSeenInCache: false) == .missing)
}

@Test("Restore drops a purchase StoreKit confirms is gone")
func testMergeRestoreDropsConfirmedRevocation() {
    let merged = mergeEntitlements(
        snapshot: EntitlementSnapshot(
            scannedIDs: [],
            lookups: ["pro": .notEntitled]
        ),
        existingIDs: ["pro"],
        sessionGrantsToKeep: ["pro"],
        mode: .restore
    )
    #expect(merged.productIDs.isEmpty)
}

@Test("Unverified transactions do not unlock and are reported when nothing else is owned")
func testMergeReportsUnverifiedWithoutGranting() {
    let merged = mergeEntitlements(
        snapshot: EntitlementSnapshot(sawUnverified: true),
        existingIDs: [],
        sessionGrantsToKeep: [],
        mode: .automatic
    )
    #expect(merged.productIDs.isEmpty)
    #expect(merged.reportUnverified == true)
}
