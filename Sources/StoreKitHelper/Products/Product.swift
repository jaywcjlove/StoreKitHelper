//
//  Product.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/8.
//

import StoreKit

public extension Product {
    /// 通过本地 `产品ID` 获取 AppStore 产品。
    static func products<T: InAppProduct>(for representations: [T]) async throws -> [Product] {
        let ids = representations.map { $0.id }
        return try await products(for: ids)
    }
}
