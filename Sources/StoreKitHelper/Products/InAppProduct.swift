//
//  InAppProduct.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/8.
//

public protocol InAppProduct: CaseIterable, Identifiable where ID == ProductID {
    var id: ProductID { get }
}

/**
 ```swift
 enum AppProduct: String, InAppProduct {
     case lifetime = "xxx.lifetime"
     case annually = "xxx.annually"
     case monthly = "xxx.monthly"
     var id: String { rawValue }
 }
 let products = AppProduct.allCases
 var store = StoreContext(products: AppProduct.allCases)
 let available = products.available(in: store)
 let purchased = products.purchased(in: store)
 ```
 */
public extension Collection where Element: InAppProduct {
    /// Get all products available in a ``StoreContext``.
    func available(in context: StoreContext) -> [Self.Element] {
        let ids = context.productIds
        return self.filter { ids.contains($0.id) }
    }
    /// Get all products purchased in a ``StoreContext``.
    func purchased(in context: StoreContext) -> [Self.Element] {
        let ids = context.purchasedProductIds
        return self.filter { ids.contains($0.id) }
    }
}
