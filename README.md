

```swift
struct ContentView: View {
    @EnvironmentObject public var store: StoreContext
    var body: some View {
        StoreKitHelperView() {
            store.isShowingPurchasePopup.toggle()
        }
        .frame(maxWidth: 320)
        .pricingContent {
            AnyView(PricingContent())
        }
        .termsOfService(label: "Terms of Service") {
            MyAppList.openURL(string: "https://wangchujiang.com/videoer/terms-of-service.html")
        }
        .privacyPolicy(label: "Privacy Policy") {
            MyAppList.openURL(string: "https://wangchujiang.com/videoer/privacy-policy.html")
        }
    }
}
```
