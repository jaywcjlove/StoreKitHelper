//
//  StoreKitHelperSelectView.swift
//  StoreKitHelper
//
//  Created by wong on 3/28/25.
//

import SwiftUI
import StoreKit

// MARK: - 选择商品付费界面
public struct StoreKitHelperSelectionView: View {
    @EnvironmentObject var store: StoreContext
    @Environment(\.pricingContent) private var pricingContent
    /// 正在`购买`中
    @State var buyingProductID: String? = nil
    /// 选中的产品ID
    @State var selectedProductID: String? = nil
    /// `产品`正在加载中...
    @State var loadingProducts: ProductsLadingStaus = .preparing
    /// 恢复购买中....
    @State var restoringPurchase: Bool = false
    var title: String? = nil
    /// 默认选择的产品 ID
    var defaultSelectedProductId: String? = nil
    public init(title: String? = nil, defaultSelectedProductId: String? = nil) {
        self.title = title
        if let defaultSelectedProductId {
            self.defaultSelectedProductId = defaultSelectedProductId
        }
    }
    public var body: some View {
        ProductsContentWrapper {
            VStack(spacing: 0) {
                HeaderView(title: title)
                Divider()
                if let pricingContent {
                    VStack(alignment: .leading, spacing: 6) {
                        pricingContent()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    Divider()
                }
                ProductsLoadList(loading: $loadingProducts) {
                    ProductsListView(selectedProductID: $selectedProductID, buyingProductID: $buyingProductID)
                        .disabled(restoringPurchase)
                }
                Divider()
                VStack {
                    HStack {
                        PurchaseButtonView(
                            selectedProductID: $selectedProductID,
                            buyingProductID: $buyingProductID,
                            loading: $loadingProducts
                        )
                        RestorePurchasesButtonView(restoringPurchase: $restoringPurchase).disabled(buyingProductID != nil)
                    }
                    .disabled(buyingProductID != nil || loadingProducts == .loading)
                }
                .padding(.trailing, 6)
                .padding(.vertical, 10)
                .disabled(restoringPurchase)
                TermsOfServiceView()
                    .padding(.bottom, 8)
#if os(macOS)
                    .buttonStyle(.link)
#endif
            }
        }
    }
}

// MARK: - 产品列表
fileprivate struct ProductsListView: View {
    @EnvironmentObject var store: StoreContext
    @Binding var selectedProductID: ProductID?
    @Binding var buyingProductID: String?
    var defaultSelectedProductId: String? = nil
    var body: some View {
        Group {
            ForEach(store.products) { product in
                let hasPurchased = store.isProductPurchased(product)
                let unit = product.subscription?.subscriptionPeriod.unit
                let isBuying = buyingProductID == product.id
                ProductListLabelView(
                    selectedProductId: $selectedProductID,
                    productId: product.id,
                    displayPrice: product.displayPrice,
                    displayName: product.displayName,
                    description: product.description,
                    hasPurchased: hasPurchased,
                    isBuying: isBuying,
                    unit: unit
                )
                .disabled(buyingProductID != nil || isDisabled(product: product))
            }
        }
        .onAppear() {
            selectedProductID = defaultSelectedProductId ?? store.productIds.first ?? ""
        }
    }
    /// 有购买，禁用`订阅`，`非消耗型`，不禁用`消耗型`
    func isDisabled(product: Product) -> Bool {
        guard store.purchasedProductIds.count > 0 else { return false }
        guard store.purchasedProductIds.contains(product.id) else {
            return true
        }
        /// 有付费产品
        let hasPurchased = store.purchasedProductIds.count > 0
        if hasPurchased == false {
            return false
        }
        /// 自动订阅
        if product.type == Product.ProductType.autoRenewable {
            return true
        }
        /// 订阅
        if product.type == Product.ProductType.nonRenewable {
            return true
        }
        /// 不可消耗的产品
        if product.type == Product.ProductType.nonConsumable {
            return true
        }
        return false
    }
}

// MARK: - 点击购买按钮
/// 点击购买按钮
struct PurchaseButtonView: View {
    @Environment(\.locale) var locale
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @Binding var selectedProductID: ProductID?
    @Binding var buyingProductID: String?
    @Binding var loading: ProductsLadingStaus
    var body: some View {
        Button(action: {
            guard let product = store.products.first(where: { $0.id == selectedProductID }) else {
                return
            }
            purchase(product: product)
        }, label: {
            HStack {
                if let buyingProductID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "cart").font(.system(size: 12))
                }
                Text("purchase".localized(locale: locale))
            }
        })
    }
    func purchase(product: Product) {
        Task {
            buyingProductID = product.id
            do {
                let (result, transaction) = try await store.purchase(product)
                if let transaction {
                    await transaction.finish()
                }
                buyingProductID = nil
                if let transaction {
                    store.updatePurchaseTransactions(with: transaction)
                } else {
                    try await store.updatePurchases()
                }
                if store.isProductPurchased(product) == true {
                    popupDismissHandle?()
                }
            } catch {
                buyingProductID = nil
                Utils.alert(title: "purchase_failed".localized(locale: locale), message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 产品详情
/// 产品详情
struct ProductListLabelView: View {
    @Binding var selectedProductId: ProductID?
    @State var hovering: Bool = false
    var productId: ProductID
    var displayPrice: String
    var displayName: String
    var description: String
    var hasPurchased: Bool
    var isBuying: Bool
    var unit: Product.SubscriptionPeriod.Unit?
    var body: some View {
        let individual = Binding(get: {
            productId == selectedProductId
        }, set: { _ in
            selectedProductId = productId
        })
        Toggle(isOn: individual, label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(displayName)
                    Text(description)
                        .foregroundStyle(.secondary).font(.system(size: 12))
                        .lineLimit(nil)  // 允许多行显示
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 2) {
                    if isBuying == true {
                        ProgressView().controlSize(.mini)
                    } else if hasPurchased == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.green)
                    } else {
                        Image(systemName: "cart").font(.system(size: 10))
                    }
                    if let localizedDescription = unit?.localizedDescription {
                        Text("\(displayPrice)").font(.system(size: 12)) + Text(" / \(localizedDescription)").font(.system(size: 10))
                    } else {
                        Text("\(displayPrice)").font(.system(size: 12))
                    }
                }
            }
            .frame(alignment: .leading)
            .disabled(hasPurchased)
            .contentShape(Rectangle())
        })
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(hovering == true ? 0.23 : 0))
        )
        .onHover(perform: { hovering in
            self.hovering = hovering
        })
    }
}

// MARK: - Header
private struct HeaderView: View {
    @Environment(\.locale) var locale
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    var title: String? = nil
    private let bundleName = {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }
    var body: some View {
        HStack(alignment: .center) {
            #if os(macOS)
                Image(nsImage: NSImage(named: NSImage.applicationIconName)!)
                    .resizable()
                    .frame(width: 28, height: 28)
            #else
            if let appIcon = Bundle.main.icon {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit() // 适应图标的比例
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 16)) // 圆角样式
                    .shadow(radius: 5) // 可选：添加阴影
                    .padding(.bottom)
                    .padding(.top)
                    .padding(.top)
            }
            #endif
            Text(title ?? "unlock_premium".localized(locale: locale)).font(.system(size: 14, weight: .bold))
            Spacer()
            if let popupDismissHandle {
                Button(action: {
                    popupDismissHandle()
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(alignment: .center)
    }
}
