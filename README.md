StoreKit Helper
===

![StoreKit Helper](https://github.com/user-attachments/assets/d0d27552-9d2d-4a09-8d8d-b96b3b3648a9)

A lightweight StoreKit2 wrapper designed specifically for SwiftUI, making it easier to implement in-app purchases.

## Documentation

Please refer to the detailed StoreKitHelper [documentation](https://github.com/jaywcjlove/devtutor) in [DevTutor](https://github.com/jaywcjlove/devtutor), which includes comprehensive examples.

## Usage

At the entry point of the SwiftUI application, create and inject a `StoreContext` instance, which is responsible for loading the product list and tracking purchase status.

```swift
import StoreKitHelper

enum AppProduct: String, CaseIterable, InAppProduct {
    case lifetime = "focuscursor.lifetime"
    case monthly = "focuscursor.monthly"
    var id: String { rawValue }
}

@main struct DevTutorApp: App {
    @StateObject var store = StoreContext(products: AppProduct.allCases)
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
```

Use `StoreKitHelperView` to directly display an in-app purchase popup view and configure various parameters through a chained API.

```swift
struct PurchaseContent: View {
    @EnvironmentObject var store: StoreContext
    var body: some View {
        StoreKitHelperView()
            .frame(maxWidth: 300)
            .frame(minWidth: 260)
            // Triggered when the popup is dismissed (e.g., user clicks the close button)
            .onPopupDismiss {
                store.isShowingPurchasePopup = false
            }
            // Sets the content area displayed in the purchase interface 
            // (can include feature descriptions, version comparisons, etc.)
            .pricingContent {
                AnyView(PricingContent())
            }
            .termsOfService {
                // Action triggered when the [Terms of Service] button is clicked
            }
            .privacyPolicy {
                // Action triggered when the [Privacy Policy] button is clicked
            }
    }
}
```

Click to open the paid product list interface.

```swift
struct PurchaseButton: View {
    @EnvironmentObject var store: StoreContext
    var body: some View {
        if store.hasNotPurchased == true {
            PurchasePopupButton()
                .sheet(isPresented: $store.isShowingPurchasePopup) {
                    /// Popup with the paid product list
                    PurchaseContent()
                }
        }
    }
}
```

You can use the `hasNotPurchased` property in `StoreContext` to check if the user has made a purchase, and then dynamically display different interface content. For example:

```swift
@EnvironmentObject var store: StoreContext

var body: some View {
    if store.hasNotPurchased == true {
        // 🧾 User has not purchased - Show restricted content or prompt for purchase
    } else {
        // ✅ User has purchased - Show full features
    }
}
```