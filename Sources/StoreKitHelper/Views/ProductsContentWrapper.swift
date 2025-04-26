//
//  ContentWrapper.swift
//  StoreKitHelper
//
//  Created by Kenny on 2025/4/4.
//

import SwiftUI

struct ViewHeightKey: PreferenceKey {
    typealias Value = CGFloat
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
