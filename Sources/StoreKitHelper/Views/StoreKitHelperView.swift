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
    @EnvironmentObject var store: StoreContext
    ///
    /// - Parameters:
    ///   - bundleName: 应用名称
    ///   - title: 标题
    public init(
        dismiss: @escaping () -> Void
    ) {
        self.dismiss = dismiss
    }
    var dismiss: () -> Void
    private let bundleName = {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }
    public var body: some View {
        VStack(spacing: 0) {
            StoreKitHelperHeaderView(dismiss: dismiss)
            Text(bundleName()).padding(.bottom, 14).foregroundStyle(.secondary).fontWeight(.bold)
            VStack(alignment: .leading, spacing: 6) {
                pricingContent?()
            }
            .padding(.top, 12)
            ProductsListView()
            TermsOfServiceView()
        }
    }
}

// MARK: - 产品列表
private struct ProductsListView: View {
    @EnvironmentObject var store: StoreContext
    @State var hovering: Bool = false
    @State var buyingProductID: String? = nil
    var body: some View {
        Divider()
        VStack {
            ForEach(store.products.sorted(by: { $0.price > $1.price })) { product in
                let unit = product.subscription?.subscriptionPeriod.unit
                let isBuying = buyingProductID == product.id
                ProductsListLabelView(
                    isBuying: .constant(isBuying),
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
            } catch {
                buyingProductID = nil
                Utils.alert(title: "purchase_failed".localized(), message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 产品列表 - item
private struct ProductsListLabelView: View {
    @EnvironmentObject var store: StoreContext
    @State var hovering: Bool = false
    @Binding var isBuying: Bool
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
            let bind = Binding(get: {
                isBuying || hovering
            }, set: { _ in })
            Button(action: {
                purchase()
            }, label: {
                HStack(spacing: 2) {
                    if isBuying == true {
                        ProgressView().controlSize(.mini)
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
            .buttonStyle(CostomPayButtonStyle(isHovered: bind))
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
    var normalColor: Color = .secondary.opacity(0.25)
    var hoverColor: Color = Color.accentColor
    func makeBody(configuration: Configuration) -> some View {
        ButtonView(isHovered: $isHovered, configuration: configuration, normalColor: normalColor, hoverColor: hoverColor)
    }
    private struct ButtonView: View {
        //@State private var isHovered = false
        @Binding var isHovered: Bool
        let configuration: Configuration
        let normalColor: Color
        let hoverColor: Color
        var body: some View {
            configuration.label
                .foregroundColor(.secondary)
                .padding(3)
                .padding(.horizontal, 3)
//                .onHover { isHovered = $0 }
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHovered ? hoverColor.opacity(configuration.isPressed ? 1 : 0.75) : normalColor)
                )
        }
    }
}

// MARK: 服务条款 & 隐私政策
private struct TermsOfServiceView: View {
    @Environment(\.termsOfServiceHandle) private var termsOfServiceHandle
    @Environment(\.privacyPolicyHandle) private var privacyPolicyHandle
    
    @Environment(\.termsOfServiceLabel) private var termsOfServiceLabel
    @Environment(\.privacyPolicyLabel) private var privacyPolicyLabel
    var body: some View {
        if termsOfServiceHandle != nil || privacyPolicyHandle != nil {
            Divider()
            HStack {
                if let action = termsOfServiceHandle {
                    Button(action: action, label: {
                        let text = termsOfServiceLabel.isEmpty == true ? "terms_of_service".localized() : termsOfServiceLabel
                        Text(text).frame(maxWidth: .infinity)
                    })
                }
                if let action = privacyPolicyHandle {
                    Button(action: action, label: {
                        let text = privacyPolicyLabel.isEmpty == true ? "privacy_policy".localized() : privacyPolicyLabel
                        Text(text).frame(maxWidth: .infinity)
                    })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 头部
private struct StoreKitHelperHeaderView: View {
    public init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }
    var dismiss: () -> Void
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
                dismiss()
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
