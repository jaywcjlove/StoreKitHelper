//
//  ContentView.swift
//  Example
//
//  Created by wong on 12/28/25.
//

import SwiftUI
import StoreKit
import StoreKitHelper

struct ContentView: View {
    @EnvironmentObject var store: StoreContext
//    @Environment(\.locale) var locale
    var body: some View {
        if store.hasNotPurchased == true {
            PurchasePopupButton()
                .sheet(isPresented: $store.isShowingPurchasePopup) {
                    PurchaseContent()
                }
        }
        let locale: Locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        PurchaseContent()
            .environment(\.locale, .init(identifier: locale.identifier))
//        PurchaseExample()
    }
}

struct PurchaseContent: View {
    @EnvironmentObject var store: StoreContext
    let locale: Locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
    var body: some View {
        StoreKitHelperView()
//        StoreKitHelperSelectionView()
            .environment(\.locale, .init(identifier: locale.identifier))
            .environment(\.pricingContent, { AnyView(PricingContent()) })
            .environment(\.popupDismissHandle, {
                store.isShowingPurchasePopup = false
            })
            .environment(\.termsOfServiceHandle, {
                // Action triggered when the [Terms of Service] button is clicked
                print("Action triggered when the [Terms of Service] button is clicked")
            })
            .environment(\.privacyPolicyHandle, {
                // Action triggered when the [Privacy Policy] button is clicked
                print("Action triggered when the [Privacy Policy] button is clicked")
            })
            .environment(\.privacyPolicyLabel, "Privacy Policy 1")
            .frame(maxWidth: 300)
            .frame(minWidth: 260)
    }
}


struct PricingContent: View {
    var body: some View {
        VStack {
            Text("Unlock all Features").font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Free").frame(width: 30, alignment: .center)
                    Text("Pro")
                }
                .font(.system(size: 12))
                Divider()
                FeaturesCheckmarkRow() {
                  Text("Move Mouse with Keyboard")
                }
                FeaturesCheckmarkRow() {
                  Text("Grid-Based Positioning")
                }
                FeaturesCheckmarkRow(features: .vip) {
                  Text("App Navigation Configuration")
                }
                FeaturesCheckmarkRow(features: .vip) {
                  Text("Keyboard-Mouse Mode Notification Settings")
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        .padding(.bottom)
    }
}

struct FeaturesCheckmarkRow<Lablel: View>: View {
    enum Feature {
        case vip, free
    }
    var features: Feature = .free
    var label: () -> Lablel
    var body: some View {
        HStack(alignment: .top) {
            HStack {
                Image(systemName: iconName).foregroundStyle(features == .free ? Color.green : Color.red)
            }
            .frame(width: 30, alignment: .center)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
            label().font(.system(size: 12, weight: .light))
        }
        .frame(alignment: .topLeading)
    }
    var iconName: String {
        features == .free ? "checkmark.circle.fill" : "xmark"
    }
}
