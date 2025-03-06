//
//  BuyButton.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//

import SwiftUI

public struct PurchasePopupButton: View {
    @EnvironmentObject public var store: StoreContext
    public init() {}
    public var body: some View {
        Button(action: {
            store.isShowingPurchasePopup.toggle()
        }) {
            Image(systemName: "cart")
        }
    }
}

