//
//  ProductsLoadList.swift
//  StoreKitHelper
//
//  Created by wong on 3/28/25.
//

import SwiftUI
import StoreKit

/// 用户更新产品列表
struct ProductsLoadList<Content: View>: View {
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @Binding var loading: LadingStaus
    @State var products: [Product] = []
    @State var error: StoreKitError? = nil
    var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if loading == .unavailable {
                ProductsUnavailableView(error: $error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.opacity(0.73))
                    .padding(8)
            } else if products.count > 0 {
                content()
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
        .onChange(of: products, initial: false, { old, val in
            if products.count > 0 {
                store.products = products
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
                        self.products = products.sorted(by: { $0.price < $1.price })
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
