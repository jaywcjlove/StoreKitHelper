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

@Test("Volume discount fills the expensive tier first")
func testMultiSeatQuoteFillsExpensiveTierFirst() throws {
    let tiers = [
        MultiSeatPriceTier(minimumSeats: 1, maximumSeats: 5, pricePerSeat: Decimal(string: "9.99")!),
        MultiSeatPriceTier(minimumSeats: 6, maximumSeats: 10, pricePerSeat: Decimal(string: "7.99")!),
    ]
    let quote = try MultiSeatPurchase.quote(seatCount: 8, tiers: tiers).get()
    #expect(quote.total == Decimal(string: "73.92"))
    #expect(quote.lines.map(\.seatCount) == [5, 3])
}

@Test("A single open-ended tier prices every seat")
func testMultiSeatQuotePerSeat() throws {
    let quote = try MultiSeatPurchase.quote(
        seatCount: 8,
        tiers: [MultiSeatPurchase.perSeatTier(pricePerSeat: Decimal(string: "9.99")!)]
    ).get()
    #expect(quote.total == Decimal(string: "79.92"))
    #expect(quote.lines.map(\.seatCount) == [8])
}

@Test("Seat quotes reject counts outside 1...100 and broken tiers")
func testMultiSeatQuoteRejectsUnsellableRequests() {
    let tier = MultiSeatPriceTier(minimumSeats: 1, maximumSeats: 5, pricePerSeat: 1)
    #expect(MultiSeatPurchase.quote(seatCount: 0, tiers: [tier]) == .failure(.invalidSeatCount))
    #expect(MultiSeatPurchase.quote(seatCount: 101, tiers: [tier]) == .failure(.exceedsGroupLimit))
    #expect(MultiSeatPurchase.quote(seatCount: 1, tiers: []) == .failure(.emptyTiers))
    #expect(MultiSeatPurchase.quote(seatCount: 6, tiers: [tier]) == .failure(.uncoveredSeat))
    let overlap = MultiSeatPriceTier(minimumSeats: 1, maximumSeats: nil, pricePerSeat: 2)
    #expect(MultiSeatPurchase.quote(seatCount: 1, tiers: [tier, overlap]) == .failure(.overlappingTier))
    let backwards = MultiSeatPriceTier(minimumSeats: 4, maximumSeats: 2, pricePerSeat: 1)
    #expect(MultiSeatPurchase.quote(seatCount: 1, tiers: [backwards]) == .failure(.invalidTier))
}

@Test("Transaction payload reports seat prices in milliunits")
func testParseMultiSeatInfoConvertsMilliunits() throws {
    let payload = """
    {
      "quantity": 8,
      "multiSeatInfo": {
        "invitationManagement": "APPLE",
        "priceTiers": [
          { "price": 9990, "quantity": 5 },
          { "price": 7990, "quantity": 3 }
        ]
      }
    }
    """.data(using: .utf8)!
    let info = try #require(parseMultiSeatInfo(from: payload))
    #expect(info.invitationManagement == .apple)
    #expect(info.revokedSeatQuantity == 0)
    #expect(info.paidTiers.map(\.seatCount) == [5, 3])
    #expect(info.paidTiers.map(\.pricePerSeat) == [Decimal(string: "9.99"), Decimal(string: "7.99")])
    #expect(parseMultiSeatInfo(from: Data("{}".utf8)) == nil)
    #expect(parseRenewalSeatCount(from: Data(#"{"renewalQuantity": 6}"#.utf8)) == 6)
}

@Test("Active seats add every transaction and subtract refunded seats")
func testCombineMultiSeatTransactions() throws {
    let first = try seatFact(id: 1, quantity: 8, revoked: 1, tiers: [(9990, 5), (7990, 3)])
    let added = try seatFact(id: 2, quantity: 4, tiers: [(7990, 4)], renewal: 12)
    let grants = combineMultiSeatGrants(facts: [added, first])
    let grant = try #require(grants["pro"])
    #expect(grant.activeSeatCount == 11)
    #expect(grant.revokedSeatCount == 1)
    #expect(grant.originalTransactionID == 100)
    #expect(grant.ownership == .purchased)
    #expect(grant.renewalSeatCount == 12)
    #expect(grant.paidTiers.map(\.seatCount) == [5, 7])
    #expect(grant.listedSeatTotal == Decimal(string: "105.88"))
}

@Test("An invited member keeps the group's seat count on their own transaction")
func testAssignedSeatTransaction() throws {
    let member = try seatFact(id: 9, quantity: 8, ownership: .assigned, invitation: "DEVELOPER")
    let grant = try #require(combineMultiSeatGrants(facts: [member])["pro"])
    #expect(grant.ownership == .assigned)
    #expect(grant.invitationManagement == .developer)
    #expect(grant.activeSeatCount == 8)
}

@Test("A cache miss keeps the previous seat grant, and a plain subscription clears it")
func testMergeMultiSeatGrants() throws {
    let previous = MultiSeatGrant(
        productID: "pro",
        activeSeatCount: 8,
        revokedSeatCount: 0,
        originalTransactionID: 100,
        ownership: .purchased,
        invitationManagement: .apple,
        paidTiers: [],
        renewalSeatCount: 8
    )
    let kept = mergeMultiSeatGrants(MultiSeatRefreshInput(
        purchasedProductIDs: ["pro"],
        previousGrants: ["pro": previous]
    ))
    #expect(kept.grants["pro"] == previous)

    let seenWithoutSeats = mergeMultiSeatGrants(MultiSeatRefreshInput(
        purchasedProductIDs: ["pro"],
        productsSeenInEntitlements: ["pro"],
        previousGrants: ["pro": previous]
    ))
    #expect(seenWithoutSeats.grants["pro"] == nil)

    let session = try seatFact(id: 4, quantity: 4)
    let added = mergeMultiSeatGrants(MultiSeatRefreshInput(
        sessionFacts: [session],
        purchasedProductIDs: ["pro"],
        productsSeenInEntitlements: ["pro"],
        previousGrants: ["pro": previous]
    ))
    #expect(added.grants["pro"]?.activeSeatCount == 4)
    #expect(added.sessionFacts == [session])

    let scanned = mergeMultiSeatGrants(MultiSeatRefreshInput(
        scannedFacts: [session],
        sessionFacts: [session],
        purchasedProductIDs: ["pro"],
        productsSeenInEntitlements: ["pro"]
    ))
    #expect(scanned.grants["pro"]?.activeSeatCount == 4)
    #expect(scanned.sessionFacts.isEmpty)
}

@Test("Only the group purchaser is blocked from buying fewer seats")
func testValidateMultiSeatPurchase() {
    #expect(validateMultiSeatPurchase(targetSeatQuantity: 12, purchaserActiveSeats: 8) == .valid)
    #expect(validateMultiSeatPurchase(targetSeatQuantity: 8, purchaserActiveSeats: 8) == .valid)
    #expect(validateMultiSeatPurchase(targetSeatQuantity: 6, purchaserActiveSeats: 8) == .seatReductionNotAllowed)
    #expect(validateMultiSeatPurchase(targetSeatQuantity: 0, purchaserActiveSeats: nil) == .invalidSeatCount)
    #expect(validateMultiSeatPurchase(targetSeatQuantity: 4, purchaserActiveSeats: nil) == .valid)
}

@Test("Multi-seat purchase options are StoreKit's seats option, or absent on this SDK")
func testMultiSeatPurchaseOptionsDoNotFallBackToQuantity() {
    let options = resolvedMultiSeatPurchaseOptions(seats: 12, suppressInvitationSheet: true)
    let seatSentinel = Product.PurchaseOption.custom(key: MultiSeatPurchaseOptionKey.unavailable, value: "seats")
    let sheetSentinel = Product.PurchaseOption.custom(key: MultiSeatPurchaseOptionKey.unavailable, value: "sheet")
    #expect(options?.contains(seatSentinel) != true)
    #expect(options?.contains(sheetSentinel) != true)
}

private func seatFact(
    id: UInt64,
    quantity: Int,
    revoked: Int = 0,
    ownership: MultiSeatOwnership = .purchased,
    invitation: String = "APPLE",
    tiers: [(Int, Int)] = [(9990, 1)],
    renewal: Int? = nil
) throws -> SeatTransactionFact {
    var info: [String: Any] = [
        "invitationManagement": invitation,
        "priceTiers": tiers.map { ["price": $0.0, "quantity": $0.1] },
    ]
    if revoked > 0 {
        info["revokedSeatQuantity"] = revoked
    }
    let data = try JSONSerialization.data(withJSONObject: ["multiSeatInfo": info])
    let renewalData = renewal.map { #"{"renewalQuantity": \#($0)}"#.data(using: .utf8)! }
    return try #require(makeSeatTransactionFact(
        transactionID: id,
        productID: "pro",
        purchasedQuantity: quantity,
        originalID: 100,
        ownership: ownership,
        jsonRepresentation: data,
        renewalSeatCount: renewalData.flatMap(parseRenewalSeatCount)
    ))
}
