//
//  StoreKitHelperView.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//

import SwiftUI
import StoreKit

public struct StoreKitHelperView: View {
    @Environment(\.pricingContent) private var pricingContent
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @State var buyingProductID: String? = nil
    public init() {}
    private let bundleName = {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }
    public var body: some View {
        VStack(spacing: 0) {
            StoreKitHelperHeaderView()
            Text(bundleName()).padding(.bottom, 14).foregroundStyle(.secondary).fontWeight(.bold)
            VStack(alignment: .leading, spacing: 6) {
                pricingContent?()
            }
            .padding(.top, 12)
            ProductsListView(buyingProductID: $buyingProductID)
            RestorePurchasesButtonView().disabled(buyingProductID != nil)
            TermsOfServiceView()
        }
    }
}

// MARK: - 产品列表
private struct ProductsListView: View {
    @Environment(\.locale) var locale
    @EnvironmentObject var store: StoreContext
    @Binding var buyingProductID: String?
    @State var hovering: Bool = false
    @State var products: [Product] = []
    var body: some View {
        Divider()
        VStack {
            ForEach(store.products.sorted(by: { $0.price > $1.price })) { product in
                let unit = product.subscription?.subscriptionPeriod.unit
                let isBuying = buyingProductID == product.id
                let isProductPurchased = store.isProductPurchased(product)
                ProductsListLabelView(
                    isBuying: .constant(isBuying),
                    productId: product.id,
                    unit: unit,
                    displayPrice: product.displayPrice,
                    displayName: product.displayName,
                    description: product.description
                ) {
                    purchase(product: product)
                }
                .id(product.id)
                .disabled(buyingProductID != nil)
            }
        }
        .frame(alignment: .top)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        Divider().padding(.horizontal, 10)
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
                try await store.updatePurchases()
            } catch {
                buyingProductID = nil
                Utils.alert(title: "purchase_failed".localized(locale: locale), message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 产品列表 - item
private struct ProductsListLabelView: View {
    @EnvironmentObject var store: StoreContext
    @State var hovering: Bool = false
    @Binding var isBuying: Bool
    var productId: ProductID
    var unit: Product.SubscriptionPeriod.Unit?
    var displayPrice: String
    var displayName: String
    var description: String
    var purchase: () -> Void
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                Text(displayName)
                VStack {
                    Text(description).foregroundStyle(.secondary).font(.system(size: 12))
                }
            }
            Spacer()
            let bind = Binding(get: { isBuying || hovering }, set: { _ in })
            let hasPurchased = store.purchasedProductIds.contains(productId)
            Button(action: {
                purchase()
            }, label: {
                HStack(spacing: 2) {
                    if isBuying == true {
                        ProgressView().controlSize(.mini)
                    } else if hasPurchased == true {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                    } else {
                        Image(systemName: "cart").font(.system(size: 10))
                    }
                    if let localizedDescription = unit?.localizedDescription {
                        Text("\(displayPrice)").font(.system(size: 12)) + Text(" / \(localizedDescription)").font(.system(size: 10))
                    } else {
                        Text("\(displayPrice)")
                    }
                }
                .contentShape(Rectangle())
            })
            .tint(unit == .none ? .blue : .green)
            .buttonStyle(CostomPayButtonStyle(isHovered: bind, hasPurchased: hasPurchased))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .background(
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(hovering == true ? 0.23 : 0))
        )
    }
}

struct CostomPayButtonStyle: ButtonStyle {
    @Binding var isHovered: Bool
    var hasPurchased: Bool = false
    var normalColor: Color = .secondary.opacity(0.25)
    var hoverColor: Color = Color.accentColor
    func makeBody(configuration: Configuration) -> some View {
        ButtonView(isHovered: $isHovered, configuration: configuration, normalColor: normalColor, hoverColor: hoverColor)
    }
    private struct ButtonView: View {
        @Binding var isHovered: Bool
        let configuration: Configuration
        let normalColor: Color
        let hoverColor: Color
        var body: some View {
            configuration.label
                .foregroundColor(.secondary)
                .padding(3)
                .padding(.horizontal, 3)
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHovered ? hoverColor.opacity(configuration.isPressed ? 1 : 0.75) : normalColor)
                )
        }
    }
}

// MARK: 恢复购买
/// 恢复购买
private struct RestorePurchasesButtonView: View {
    @Environment(\.locale) var locale
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @State var restoringPurchase: Bool = false
    var body: some View {
        Button(action: {
            Task {
                restoringPurchase = true
                do {
                    await try store.restorePurchases()
                    restoringPurchase = false
                    popupDismissHandle?()
                } catch {
                    restoringPurchase = false
                    Utils.alert(title: "restore_purchases_failed".localized(locale: locale), message: error.localizedDescription)
                }
            }
        }, label: {
            HStack {
                if restoringPurchase {
                    ProgressView().controlSize(.mini)
                }
                Text("restore_purchases".localized(locale: locale))
            }
        })
        .buttonStyle(.link)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .disabled(restoringPurchase)
    }
}

// MARK: 服务条款 & 隐私政策
private struct TermsOfServiceView: View {
    @Environment(\.termsOfServiceHandle) private var termsOfServiceHandle
    @Environment(\.privacyPolicyHandle) private var privacyPolicyHandle
    
    @Environment(\.termsOfServiceLabel) private var termsOfServiceLabel
    @Environment(\.privacyPolicyLabel) private var privacyPolicyLabel
    @Environment(\.locale) var locale
    var body: some View {
        if termsOfServiceHandle != nil || privacyPolicyHandle != nil {
            Divider()
            HStack {
                if let action = termsOfServiceHandle {
                    Button(action: action, label: {
                        let text = termsOfServiceLabel.isEmpty == true ? "terms_of_service".localized(locale: locale) : termsOfServiceLabel
                        Text(text).frame(maxWidth: .infinity)
                    })
                }
                if let action = privacyPolicyHandle {
                    Button(action: action, label: {
                        let text = privacyPolicyLabel.isEmpty == true ? "privacy_policy".localized(locale: locale) : privacyPolicyLabel
                        Text(text).frame(maxWidth: .infinity)
                    })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Header
private struct StoreKitHelperHeaderView: View {
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack {
                Image(nsImage: NSImage(named: NSImage.applicationIconName)!)
                    .resizable()
                    .frame(width: 76, height: 76)
            }
            .padding(.top, 23)
            .frame(maxWidth: .infinity, alignment: .center)
            Button(action: {
                popupDismissHandle?()
            }, label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 22))
            })
            .padding(.trailing, 10)
            .padding(.top, 10)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
    }
}
