//
//  OfferCodeRedemptionButton.swift
//  StoreKitHelper
//
//  Created by wong on 5/23/26.
//

import SwiftUI

// MARK: 优惠代码兑换
/// 优惠代码兑换
struct OfferCodeRedemptionButton: View {
    @Environment(\.locale) var locale
    @EnvironmentObject var store: StoreContext

    var body: some View {
        #if os(iOS) || os(macOS) || os(visionOS)
        if #available(iOS 16.0, macOS 15.0, visionOS 1.0, *) {
            Button(action: {
                store.presentOfferCodeRedemption()
            }, label: {
                HStack(spacing: 1) {
                    Image(systemName: "ticket")
#if os(macOS)
                        .font(.system(size: 12))
#endif
                    Text("redeem_offer_code", bundle: .module)
                }
            })
#if os(macOS)
            .buttonStyle(.link)
#endif
            .environment(\.locale, locale)
        }
        #endif
    }
}
