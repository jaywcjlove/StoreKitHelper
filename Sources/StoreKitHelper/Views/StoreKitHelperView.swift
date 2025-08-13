//
//  StoreKitHelperView.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//

import SwiftUI
import StoreKit


public enum ProductsLoadingStatus {
    /// Loading
    case loading
    /// Preparing to load
    case preparing
    /// Completed loading
    case complete
    /// Unavailable
    case unavailable
}

// MARK: - 默认付费界面
public struct StoreKitHelperView: View {
    @Environment(\.pricingContent) private var pricingContent
    @EnvironmentObject var store: StoreContext
    @ObservedObject var viewModel = ProductsListViewModel()
    /// 正在`购买`中
    @State var buyingProductID: String? = nil
    /// `产品`正在加载中...
    @State var loadingProducts: ProductsLoadingStatus = .preparing
    /// 恢复购买中....
    @State var restoringPurchase: Bool = false
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            VStack(alignment: .leading, spacing: 6) {
                pricingContent?()
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            Divider()
            ProductsLoadList(loading: $loadingProducts) {
                ProductsListView(buyingProductID: $buyingProductID, loading: $loadingProducts)
                    .filteredProducts() { productID, product in
                        if let filteredProducts = viewModel.filteredProducts {
                            return filteredProducts(productID, product)
                        }
                        return true
                    }
                    .disabled(restoringPurchase)
            }
            if loadingProducts == .complete || loadingProducts == .loading {
                Divider()
                HStack {
                    RestorePurchasesButtonView(restoringPurchase: $restoringPurchase).disabled(buyingProductID != nil)
                }
                .padding(.vertical, 10)
            }
#if os(iOS)
            Spacer()
#endif
        }
        .frame(minWidth: 230)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                TermsOfServiceView()
                    .padding(.top, 0)
                    .padding(.bottom, 8)
            }
        }
    }
    /**
     Filter the product list to display products based on product IDs
     
    ```swift
    StoreKitHelperView()
        .filteredProducts() { productID, product in
            return true
        }
    ```
     */
    public func filteredProducts(_ filtered: ((String, Product) -> Bool)?) -> StoreKitHelperView {
        viewModel.filteredProducts = filtered
        return self
    }
}

class ProductsListViewModel: ObservableObject {
    @Published var filteredProducts: ((String, Product) -> Bool)?
}

// MARK: - Products List
private struct ProductsListView: View {
    @Environment(\.locale) var locale
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @ObservedObject var viewModel = ProductsListViewModel()
    @Binding var buyingProductID: String?
    @Binding var loading: ProductsLoadingStatus
    @State var hovering: Bool = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.products) { product in
                let unit = product.subscription?.subscriptionPeriod.unit
                let period = product.subscription?.subscriptionPeriod
                let isBuying = buyingProductID == product.id
                let hasPurchased = store.isProductPurchased(product)
                if let filteredProducts = viewModel.filteredProducts {
                    let shouldDisplay = filteredProducts(product.id, product)
                    if shouldDisplay == true {
                        ProductsListLabelView(
                            isBuying: .constant(isBuying),
                            productId: product.id,
                            unit: unit,
                            period: period,
                            displayPrice: product.displayPrice,
                            displayName: product.displayName,
                            description: product.description,
                            hasPurchased: hasPurchased
                        ) {
                            purchase(product: product)
                        }
                        .id(product.id)
                        .disabled(buyingProductID != nil)
                    }
                } else {
                    ProductsListLabelView(
                        isBuying: .constant(isBuying),
                        productId: product.id,
                        unit: unit,
                        period: period,
                        displayPrice: product.displayPrice,
                        displayName: product.displayName,
                        description: product.description,
                        hasPurchased: hasPurchased
                    ) {
                        purchase(product: product)
                    }
                    .id(product.id)
                    .disabled(buyingProductID != nil)
                }
            }
        }
    }
    func purchase(product: Product) {
        Task {
            buyingProductID = product.id
            do {
                let (_, transaction) = try await store.purchase(product)
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
    
    public func filteredProducts(_ filtered: ((String, Product) -> Bool)?) -> ProductsListView {
        viewModel.filteredProducts = filtered
        return self
    }
}

// MARK: - Products List - item
private struct ProductsListLabelView: View {
    @EnvironmentObject var store: StoreContext
    @State var hovering: Bool = false
    @Binding var isBuying: Bool
    var productId: ProductID
    var unit: Product.SubscriptionPeriod.Unit?
    /// Subscription Period
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
            let bind = Binding(get: { isBuying || hovering }, set: { _ in })
            Button(action: {
                purchase()
            }, label: {
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
                .foregroundStyle(hovering == true ? Color.white : Color.accentColor)
            })
            .tint(unit == .none ? .blue : .green)
            .buttonStyle(CostomPayButtonStyle(isHovered: bind, hasPurchased: hasPurchased))
            .disabled(hasPurchased)
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
    @Binding var isHovered: Bool
    var hasPurchased: Bool = false
    var normalColor: Color = .secondary.opacity(0.25)
    var hoverColor: Color = Color.accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.secondary)
            .padding(3)
            .padding(.horizontal, 3)
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
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
            #else
            if let appIcon = Bundle.main.icon {
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

#if os(iOS)
extension Bundle {
    public var icon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return nil
    }
}
#endif
