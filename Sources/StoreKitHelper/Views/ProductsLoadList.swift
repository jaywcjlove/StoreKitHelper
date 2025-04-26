//
//  ProductsLoadList.swift
//  StoreKitHelper
//
//  Created by wong on 3/28/25.
//

import SwiftUI
import StoreKit

/// 用户更新产品列表
public struct ProductsLoadList<Content: View>: View {
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @Binding var loading: ProductsLoadingStatus
    @State var products: [Product] = []
    @State var error: StoreKitError? = nil
    public init(loading: Binding<ProductsLoadingStatus>, @ViewBuilder content: @escaping () -> Content) {
        self._loading = loading
        self.content = content
    }
    var content: () -> Content
    
    @State private var viewHeight: CGFloat? = nil
    public var body: some View {
        ZStack {
            if loading == .unavailable {
                ProductsUnavailableView(error: $error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.opacity(0.73))
                    .padding(8)
            } else if store.products.count > 0 {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
        .overlay(content: {
            if loading == .loading {
                VStack {
                    ProgressView().controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.73))
            }
        })
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ViewHeightKey.self, value: geometry.size.height)
        })
        .onPreferenceChange(ViewHeightKey.self) { newHeight in
            DispatchQueue.main.async {
                self.viewHeight = newHeight
            }
        }
        .frame(minHeight: viewHeight)
        .onChange(of: products, initial: false, { old, val in
            if products.count > 0 {
                let productIdSet = Set(store.productIds)
                /// 根据 id 进行排序
                store.products = products.filter { productIdSet.contains($0.id) }
                    .sorted {
                        if let index1 = store.productIds.firstIndex(of: $0.id),
                           let index2 = store.productIds.firstIndex(of: $1.id) {
                            return index1 < index2
                        }
                        return false
                    }
            }
        })
        .padding(6)
        .onAppear() {
            loading = .loading
            error = nil
            Task {
                do {
                    let products = try await store.getProducts()
                    if products.count == 0, store.products.count == 0 {
                        loading = .unavailable
                        return
                    } else if products.count > 0 {
                        self.products = products
                    }
                    loading = .complete
                } catch {
                    loading = .unavailable
                    self.error = error as? StoreKitError
                }
            }
        }
    }
}
