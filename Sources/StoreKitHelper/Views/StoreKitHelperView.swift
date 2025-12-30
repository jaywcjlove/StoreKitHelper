//
//  StoreKitHelperView.swift
//  StoreKitHelper
//
//  Created by wong on 12/28/25.
//

import SwiftUI
import StoreKit

// MARK: - 默认付费界面
public struct StoreKitHelperView: View {
    @Environment(\.locale) var locale
    @EnvironmentObject var store: StoreContext
    @Environment(\.pricingContent) private var pricingContent
    /// 恢复购买中....
    @State var restoringPurchase: Bool = false
    /// 正在`购买`中
    @State var buyingProductID: String? = nil
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            if let pricingContent {
                VStack(alignment: .leading, spacing: 6) {
                    pricingContent()
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            Divider()
            ProductsLoadList(buyingProductID: $buyingProductID)
                .padding(6)
            Divider()
            HStack {
                RestorePurchasesButton(restoringPurchase: $restoringPurchase)
            }
            .padding(.vertical, 10)
            .disabled(buyingProductID != nil || store.isLoading)
        }
        .frame(minWidth: 230)
        .frame(maxWidth: .infinity)
        .environment(\.locale, locale)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                TermsOfServiceView()
                    .padding(.top, 0)
                    .padding(.bottom, 8)
            }
        }
    }
}


struct ProductsLoadList: View {
    @Environment(\.locale) var locale
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @Binding var buyingProductID: String?
    var body: some View {
        ProductsLoad {
            let products = store.productsSorted()
            ForEach(products, id: \.id) { product in
                let unit = product.subscription?.subscriptionPeriod.unit
                let period = product.subscription?.subscriptionPeriod
                let hasPurchased = store.isPurchased(product.id)
                let isBuying = buyingProductID == product.id
                ProductsListLabelView(
                    isBuying: isBuying,
                    unit: unit,
                    period: period,
                    displayPrice: product.displayPrice,
                    displayName: product.displayName,
                    description: product.description,
                    hasPurchased: hasPurchased,
                ) {
                    purchase(product: product)
                }
                .disabled(buyingProductID != nil)
            }
        }
    }
    func purchase(product: Product) {
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

// MARK: - Products List - item
private struct ProductsListLabelView: View {
    @State var hovering: Bool = false
    var isBuying: Bool
    var unit: Product.SubscriptionPeriod.Unit?
    var period: Product.SubscriptionPeriod?
    var displayPrice: String
    var displayName: String
    var description: String
    var hasPurchased: Bool
    var purchase: () -> Void
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                Text(displayName)
                Text(description).foregroundStyle(.secondary).font(.system(size: 12))
                    .lineLimit(nil)  // 允许多行显示
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: {
                purchase()
            }) {
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
                    if let period = period {
                        let periodString = "\(period.value) \(period.unit.localizedDescription)"
                        Text("\(displayPrice) / ").font(.system(size: 12)) + Text("\(periodString)").font(.system(size: 10))
                    } else if let localizedDescription = unit?.localizedDescription {
                        Text("\(displayPrice) / ").font(.system(size: 12)) + Text("\(localizedDescription)").font(.system(size: 10))
                    } else {
                        Text("\(displayPrice)").font(.system(size: 12))
                    }
                }
                .font(.system(size: 12))
                .contentShape(Rectangle())
                .foregroundStyle(hovering == true ? Color.secondary : Color.primary)
            }
            .tint(unit == .none ? .blue : .green)
            .buttonStyle(CostomPayButtonStyle(isHovered: hovering, hasPurchased: hasPurchased))
            .disabled(hasPurchased || isBuying)
#if os(macOS)
            .onHover { isHovered in
                if isHovered, hasPurchased {
                    NSCursor.operationNotAllowed.push()
                } else if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onAppear() {
                NSCursor.pop()
            }
#endif
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .onHover { isHovered in
            withAnimation {
                hovering = isHovered
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(hovering == true ? 0.23 : 0))
        )
    }
}


struct CostomPayButtonStyle: ButtonStyle {
    var isHovered: Bool
    var hasPurchased: Bool = false
    var normalColor: Color = .secondary.opacity(0.25)
    var hoverColor: Color = Color.accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.secondary)
            .padding(3)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered || hasPurchased ? hoverColor.opacity(configuration.isPressed ? 1 : 0.75) : normalColor)
            )
    }
}

// MARK: - Header
private struct HeaderView: View {
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    private let bundleName = {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }
    var body: some View {
        VStack {
            #if os(macOS)
                Image(nsImage: NSImage(named: NSImage.applicationIconName)!)
                    .resizable()
                    .frame(width: 76, height: 76)
            #endif
            #if canImport(UIKit)
            if let appIcon = UIApplication.applicationIconImage() {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit() // 适应图标的比例
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 16)) // 圆角样式
                    .shadow(radius: 5) // 可选：添加阴影
                    .padding(.bottom)
                    .padding(.top)
                    .padding(.top)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let popupDismissHandle {
                HStack {
                    Spacer()
                    Button(action: {
                        popupDismissHandle()
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 22))
                    })
        #if os(macOS)
                    .padding(.trailing, 10)
                    .padding(.top, 10)
        #else
                    .padding(.top)
        #endif
                    .buttonStyle(.plain)
                }
                .frame(alignment: .topTrailing)
                .frame(height: 32)
            }
        }
        if #available(iOS 16.0, *) {
            Text(bundleName()).padding(.bottom, 6).foregroundStyle(.secondary).fontWeight(.bold)
        } else {
            Text(bundleName()).padding(.bottom, 6).foregroundStyle(.secondary)
        }
    }
}
