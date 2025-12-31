//
//  StoreKitHelperSelectionView.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import SwiftUI
import StoreKit

// MARK: - 选择商品付费界面
public struct StoreKitHelperSelectionView: View {
    @Environment(\.pricingContent) private var pricingContent
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @Environment(\.locale) var locale
    @EnvironmentObject var store: StoreContext
    /// 恢复购买中....
    @State var restoringPurchase: Bool = false
    /// 默认选择的产品 ID
    var defaultSelectedProductId: String? = nil
    /// 正在`购买`中
    @State var buyingProductID: String? = nil
    /// 选中的产品ID
    @State var selectedProductID: String? = nil
    var title: String? = nil
    public init(title: String? = nil, defaultSelectedProductId: String? = nil) {
        self.title = title
        self.selectedProductID = defaultSelectedProductId
    }
    public var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: title)
            Divider()
            if let pricingContent {
                VStack(alignment: .leading, spacing: 6) {
                    pricingContent()
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
                #if os(iOS)
                Spacer()
                #endif
                Divider()
            }
            
            ProductsLoad {
                let products = store.productsSorted()
                ForEach(products, id: \.id) { product in
                    let unit = product.subscription?.subscriptionPeriod.unit
                    let period = product.subscription?.subscriptionPeriod
                    let hasPurchased = store.isPurchased(product.id)
                    let isBuying = buyingProductID == product.id
                    ProductsListLabelView(
                        selectedProductId: $selectedProductID,
                        productId: product.id,
                        displayPrice: product.displayPrice,
                        displayName: product.displayName,
                        description: product.description,
                        hasPurchased: hasPurchased,
                        isBuying: isBuying,
                        period: period,
                        unit: unit
                    )
                    .disabled(buyingProductID != nil)
                }
            }
            .padding(6)
        
            Divider()
            
            VStack {
                HStack {
                    Button(action: {
                        guard let product = store.products.first(where: { $0.id == selectedProductID }) else {
                            return
                        }
                        purchase(product: product)
                    }, label: {
                        HStack {
                            if buyingProductID != nil {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "cart")
#if os(macOS)
                                    .font(.system(size: 12))
#endif
                            }
                            Text("purchase", bundle: .module)
                        }
                        .glassEffectButton(color: Color.accentColor)
#if os(iOS)
                        .font(.system(size: 16))
#endif
                    })
                    .glassButtonStyle()
                    .tint(.accentColor)
                    RestorePurchasesButton(restoringPurchase: $restoringPurchase)
                }
                .disabled(buyingProductID != nil || store.isLoading)
            }
            .padding(.trailing, 6)
            .padding(.vertical, 10)
        }
        .onAppear() {
            selectedProductID = defaultSelectedProductId ?? store.productIDs.first ?? ""
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                TermsOfServiceView()
#if os(macOS)
                    .buttonStyle(.link)
#endif
                    .padding(.top, 0)
                    .padding(.bottom, 8)
            }
        }
    }
    func purchase(product: Product) {
        let purchaseFailed = String.localizedString(key: "purchase_failed", locale: locale)
        Task {
            buyingProductID = product.id
            await store.purchase(product)
            buyingProductID = nil
            if store.isPurchased(product.id) == true {
                popupDismissHandle?()
            }
        }
    }
}

private struct ProductsListLabelView: View {
    @Binding var selectedProductId: ProductID?
    @State var hovering: Bool = false
    var productId: ProductID
    var displayPrice: String
    var displayName: String
    var description: String
    var hasPurchased: Bool
    var isBuying: Bool
    /// Subscription Period
    var period: Product.SubscriptionPeriod?
    var unit: Product.SubscriptionPeriod.Unit?
    var body: some View {
        let individual = Binding(get: {
            productId == selectedProductId
        }, set: { _ in
            selectedProductId = productId
        })
        
        Toggle(isOn: individual) {
#if os(macOS)
            let fontSize: CGFloat = 12
            let fontSizeLast: CGFloat = 10
#else
            let fontSize: CGFloat = 16
            let fontSizeLast: CGFloat = 12
#endif
            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text(displayName)
                    Text(description).foregroundStyle(.secondary).font(.system(size: 12))
                        .lineLimit(nil)  // 允许多行显示
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 2) {
                    if isBuying == true {
#if os(macOS)
                        ProgressView().controlSize(.mini)
#else
                        ProgressView().tint(.primary)
#endif
                    } else if hasPurchased == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: fontSizeLast))
                            .foregroundStyle(Color.green)
                    } else {
                        Image(systemName: "cart").font(.system(size: fontSizeLast))
                    }
                    if let period = period {
                        let periodString = "\(period.value) \(period.unit.localizedDescription)"
                        Text("\(displayPrice) / ").font(.system(size: fontSize)) + Text("\(periodString)").font(.system(size: fontSizeLast))
                    } else if let localizedDescription = unit?.localizedDescription {
                        Text("\(displayPrice) / ").font(.system(size: fontSize)) + Text("\(localizedDescription)").font(.system(size: fontSizeLast))
                    } else {
                        Text("\(displayPrice)").font(.system(size: fontSize))
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        #if os(macOS)
        .background(
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(hovering == true ? 0.23 : 0))
        )
        .onHover(perform: { hovering in
            self.hovering = hovering
        })
        #else
        .toggleStyle(.button)
        #endif
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
            #endif
            #if canImport(UIKit)
            if let appIcon = UIApplication.applicationIconImage() {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit() // 适应图标的比例
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8)) // 圆角样式
                    .shadow(radius: 5) // 可选：添加阴影
                    .padding(.bottom)
                    .padding(.top)
            }
            #endif
            Text(title != nil ? LocalizedStringKey(title ?? "")  : "unlock_premium", bundle: .module)
#if os(macOS)
                .font(.system(size: 14, weight: .bold))
#endif
#if canImport(UIKit)
                .font(.system(size: 20, weight: .bold))
#endif
            Spacer()
            if let popupDismissHandle {
                Button(action: {
                    popupDismissHandle()
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
#if os(macOS)
                        .font(.system(size: 18))
#endif
#if canImport(UIKit)
                        .font(.system(size: 28))
#endif
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(alignment: .center)
    }
}
