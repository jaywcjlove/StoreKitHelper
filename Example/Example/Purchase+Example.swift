//
//  Purchase+Example.swift
//  Example
//
//  Created by wong on 12/28/25.
//

import SwiftUI
import StoreKit
import StoreKitHelper

struct PurchaseExample: View {
    @EnvironmentObject var store: StoreContext
//    @Environment(\.locale) var locale
    var body: some View {
        let locale: Locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        VStack(spacing: 20) {
            // 状态显示
            statusSection
            Divider()
            
            // 产品列表
            if store.isLoading {
                ProgressView("加载产品中...")
            } else {
                productsSection
            }
            
            Divider()
            
            // 功能区域
            featureSection
            
            Spacer()
            
            // 恢复购买按钮
            Button("恢复购买") {
                Task {
                    await store.restorePurchases()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .alert("错误", isPresented: .constant(store.storeError != nil)) {
            Button("确定") {
                // 清除错误信息的逻辑可以在这里添加
            }
        } message: {
            Text(store.storeError?.description(locale: locale) ?? "")
        }
    }
    // MARK: - 状态显示区域
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("购买状态")
                .font(.headline)
            HStack {
                Image(systemName: store.hasPurchased ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(store.hasPurchased ? .green : .red)
                
                Text(store.hasPurchased ? "已购买" : "未购买")
                    .font(.subheadline)
                
                Spacer()
            }
            
            if !store.purchasedProductIDs.isEmpty {
                Text("已购买产品: \(Array(store.purchasedProductIDs).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cornerRadius(8)
    }
    
    // MARK: - 产品列表区域
    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可购买产品")
                .font(.headline)
            
            ForEach(store.products, id: \.id) { product in
                ProductRow(product: product)
            }
            
            if store.products.isEmpty {
                Text("暂无可购买的产品")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    // MARK: - 功能区域
    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用功能")
                .font(.headline)
            
            if store.hasNotPurchased {
                VStack(alignment: .leading, spacing: 8) {
                    Text("🔒 受限功能")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    Text("请购买产品以解锁完整功能")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✅ 完整功能已解锁")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    
                    Text("感谢您的支持！您可以使用所有功能")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}


// MARK: - 产品行视图
struct ProductRow: View {
    let product: Product
    @EnvironmentObject var store: StoreContext
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(product.displayPrice)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if store.isPurchased(product.id) {
                    Text("已购买")
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                } else {
                    Button("购买") {
                        Task {
                            await store.purchase(product)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .cornerRadius(8)
    }
}
