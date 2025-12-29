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
        #expect(store.hasNotPurchased == true)
        #expect(store.hasPurchased == false)
    }
}

@Test("Purchase status check methods") 
func testPurchaseStatusMethods() async throws {
    let store = await StoreContext(products: TestProduct.allCases)
    
    await MainActor.run {
        // 测试购买状态检查方法
        #expect(store.isPurchased("test.basic") == false)
        #expect(store.isPurchased(TestProduct.premium) == false)
        // 模拟购买状态（仅在测试中使用）
        store._setPurchasedProductIDsForTesting(["test.basic"])
        #expect(store.isPurchased("test.basic") == true)
        #expect(store.isPurchased(TestProduct.basic) == true)
        #expect(store.isPurchased("test.premium") == false)
        #expect(store.hasPurchased == true)
        #expect(store.hasNotPurchased == false)
    }
}
