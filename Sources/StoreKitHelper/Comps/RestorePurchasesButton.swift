//
//  RestorePurchasesButton.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//


import SwiftUI

// MARK: 恢复购买
/// 恢复购买
struct RestorePurchasesButton: View {
    @Environment(\.locale) var locale
    @Environment(\.popupDismissHandle) private var popupDismissHandle
    @EnvironmentObject var store: StoreContext
    @Binding var restoringPurchase: Bool
    func showError(error: StoreKitError?) -> Bool {
        guard let error else { return false }
        guard error != .userCancelled else { return false }
        guard case .restoreFailed = error else { return true }
        return false
    }
    var body: some View {
        let noPurchaseTitle = String.localizedString(key: "no_purchase_available", locale: locale)
        let restoreFailedTitle = String.localizedString(key: "restore_purchases_failed", locale: locale)
        Button(action: {
            Task {
                restoringPurchase = true
                do {
                    try await store.restorePurchases()
                    restoringPurchase = false
                    if store.purchasedProductIDs.count > 0 {
                        popupDismissHandle?()
                    } else if showError(error: store.storeError) == true {
                        NotifyAlert.alert(title: store.storeError?.description(locale: locale) ??  noPurchaseTitle, message: "")
                    }
                } catch {
                    restoringPurchase = false
                    NotifyAlert.alert(title: restoreFailedTitle, message: error.localizedDescription)
                }
            }
        }, label: {
            HStack {
                if restoringPurchase {
                    ProgressView().controlSize(.mini)
                }
                Text("restore_purchases", bundle: .module)
            }
        })
        #if os(macOS)
        .buttonStyle(.link)
        #endif
        .disabled(restoringPurchase)
        .environment(\.locale, locale)
    }
}
