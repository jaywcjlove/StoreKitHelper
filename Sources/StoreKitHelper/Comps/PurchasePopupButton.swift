//
//  PurchasePopupButton.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import SwiftUI

public struct PurchasePopupButton<LabelView: View>: View {
    @EnvironmentObject public var store: StoreContext
    var label: (() -> LabelView)?
    public init(label: (() -> LabelView)? = nil) {
        self.label = label
    }
    public var body: some View {
        if store.hasNotPurchased == true, store.isLoading == false {
            Button(action: {
                store.isShowingPurchasePopup.toggle()
            }) {
                if let label {
                    label()
                } else {
                    Image(systemName: "cart")
                }
            }
        }
    }
}

public extension PurchasePopupButton where LabelView == EmptyView {
    init() {
        self.init(label: nil)
    }
}
