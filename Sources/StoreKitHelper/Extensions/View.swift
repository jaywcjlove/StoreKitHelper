//
//  View.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//


import SwiftUI

internal extension View {
//    @ViewBuilder func glassEffectButton() -> some View {
//        if #available(macOS 26.0, iOS 26, *) {
//            self.buttonStyle(.plain)
//                .padding(.vertical, 5)
//                .glassEffect(.regular.interactive(), in: .capsule)
//        } else {
//            self
//        }
//    }
    @ViewBuilder func glassEffectButton(in shape: some Shape = .capsule, color: Color? = nil) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .glassEffect(color != nil ? .regular.tint(color): .regular, in: shape)
        } else {
            self.tint(color)
        }
    }
    @ViewBuilder func glassButtonStyle() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.buttonStyle(.plain)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
