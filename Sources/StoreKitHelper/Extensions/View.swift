//
//  View.swift
//  StoreKitHelper
//
//  Created by wong on 10/1/25.
//

import SwiftUI

internal extension View {
    @ViewBuilder func glassEffectButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.plain)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
        }
    }
}
