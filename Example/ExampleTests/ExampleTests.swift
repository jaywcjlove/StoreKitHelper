//
//  ExampleTests.swift
//  ExampleTests
//
//  Created by wong on 12/28/25.
//

import Testing
import StoreKit
import StoreKitTest

@testable import StoreKitHelper

enum AppProduct: String, InAppProduct {
    case lifetime = "test.lifetime"
    case monthly = "test.monthly"
    var id: String { rawValue }
}

@Suite(.serialized) // 强制串行执行测试，避免并发问题
final class StoreKitNetworkErrorTests {
    private func makeSession() throws -> SKTestSession {
        guard let url = Bundle.main.url(forResource: "Configuration", withExtension: "storekit") else {
            Issue.record("找不到 Configuration.storekit，请确认 Package.swift resources")
            throw NSError(domain: "TestError", code: -1)
        }
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        session.resetToDefaultState()
        return session
    }
    
    /// 辅助方法：等待并验证购买状态更新
    private func waitAndVerifyPurchaseState(store: StoreContext, expectedHasPurchased: Bool, expectedProductID: String? = nil, timeout: Duration = .milliseconds(1000)) async throws {
        let startTime = Date()
        let timeoutInterval = TimeInterval(timeout.components.seconds) + TimeInterval(timeout.components.attoseconds) / 1_000_000_000_000_000_000
        
        while Date().timeIntervalSince(startTime) < timeoutInterval {
            await store.restorePurchases()
            try await Task.sleep(for: .milliseconds(100))
            
            let currentState = await store.hasPurchased
            if currentState == expectedHasPurchased {
                if let productID = expectedProductID {
                    let hasProduct = await store.isPurchased(productID)
                    if hasProduct == expectedHasPurchased {
                        return
                    }
                } else {
                    return
                }
            }
        }
        
        // 如果超时，记录当前状态用于调试
        let finalState = await store.hasPurchased
        let finalProductIDs = await store.purchasedProductIDs
        Issue.record("等待购买状态更新超时. 期望 hasPurchased: \(expectedHasPurchased), 实际: \(finalState), 产品IDs: \(finalProductIDs)")
    }
    
    @Test("StoreContext initialization")
    func testStoreContextInitialization() async throws {
        let session = try makeSession()
        let store = await StoreContext(products: AppProduct.allCases)
        try await Task.sleep(for: .milliseconds(500))
        #expect(await store.products.count == 2)
        #expect(await store.purchasedProductIDs.count == 0)
        #expect(await store.hasNotPurchased == true)
        #expect(await store.hasPurchased == false)
        let product = await store.products.first(where: { $0.id == AppProduct.lifetime.id })
        #expect(product != nil)
        #expect(product?.id == AppProduct.lifetime.id)
        session.clearTransactions()
        session.resetToDefaultState()
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
    }
    
    @Test("InAppProduct networkError when loading products")
    func testNetworkErrorStrict() async throws {
        let session = try makeSession()
        let urlError = URLError(.cannotConnectToHost)
        try await session.setSimulatedError(.generic(.networkError(urlError)), forAPI: .loadProducts)
        let store = await StoreContext(products: AppProduct.allCases)
        /// 异步
        try await Task.sleep(for: .milliseconds(500))
        #expect(await store.products.count == 0)
        #expect(await store.purchasedProductIDs.count == 0)
        #expect(await store.hasNotPurchased == true)
        #expect(await store.hasPurchased == false)
        session.clearTransactions()
        session.resetToDefaultState()
        //try await Task.sleep(for: .seconds(5))
    }
    
    @Test func testPurchaseSuccess() async throws {
        let session = try makeSession()
        let store = await StoreContext(products: AppProduct.allCases)
        /// 异步
        try await Task.sleep(for: .milliseconds(500))
        #expect(await store.products.count == 2)
        #expect(await store.purchasedProductIDs.count == 0)
        #expect(await store.hasNotPurchased == true)
        #expect(await store.hasPurchased == false)
        let lifetime = await store.products.first(where: { $0.id == AppProduct.lifetime.id })
        #expect(lifetime != nil)
        #expect(lifetime?.id == AppProduct.lifetime.id)
        if let lifetime {
            session.disableDialogs = true
            await store.purchase(lifetime)
        }
        #expect(await store.hasPurchased == true)
        #expect(await store.purchasedProductIDs.contains(AppProduct.lifetime.id) == true)
        session.clearTransactions()
        session.resetToDefaultState()
        #expect(await store.hasPurchased == true)
        #expect(await store.purchasedProductIDs.contains(AppProduct.lifetime.id) == true)
        session.disableDialogs = true
        await store.restorePurchases()
        #expect(await store.hasPurchased == false)
        session.clearTransactions()
        session.resetToDefaultState()
    }
    
    @Test("Purchase and expire monthly subscription")
    func testMonthlySubscriptionPurchaseAndExpiry() async throws {
        let session = try makeSession()
        // 设置快速时间流逝，月度订阅每30秒续订一次
        //session.timeRate = SKTestSession.TimeRate.monthlyRenewalEveryThirtySeconds
        let store = await StoreContext(products: AppProduct.allCases)
        try await Task.sleep(for: .milliseconds(500))
        
        let monthly = await store.products.first(where: { $0.id == AppProduct.monthly.id })
        #expect(monthly != nil)
        #expect(monthly?.id == AppProduct.monthly.id)
        if let monthly {
            session.disableDialogs = true
            // 购买订阅
            await store.purchase(monthly)
        }
            
        // 验证购买成功
        #expect(await store.hasPurchased == true)
        #expect(await store.purchasedProductIDs.contains(AppProduct.monthly.id) == true)
        
        // 直接让订阅过期
        try session.expireSubscription(productIdentifier: AppProduct.monthly.id)
        
        // 更新购买状态
        session.disableDialogs = true
        await store.restorePurchases()
        
        // 验证订阅已过期
        #expect(await store.purchasedProductIDs.contains(AppProduct.monthly.id) == false)
        #expect(await store.hasPurchased == false)
        
        // 清理
        session.clearTransactions()
        session.resetToDefaultState()
    }
}
