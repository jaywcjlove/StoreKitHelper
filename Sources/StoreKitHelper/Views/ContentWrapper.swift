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

struct ContentWrapper<Content: View>: View {
    @State private var viewHeight: CGFloat = 0
    var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ViewHeightKey.self, value: geometry.size.height)
        })
        .onPreferenceChange(ViewHeightKey.self) { newHeight in
            DispatchQueue.main.async {
                self.viewHeight = newHeight
            }
        }
        .frame(minHeight: viewHeight)
    }
}
