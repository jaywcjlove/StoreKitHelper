//
//  ProductsLoad.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import SwiftUI


struct ViewHeightKey: PreferenceKey {
    typealias Value = CGFloat
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct ProductsLoad<Content: View>: View {
    @Environment(\.locale) var locale
    @EnvironmentObject var store: StoreContext
    @State private var viewHeight: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    func showError(error: StoreKitError?) -> Bool {
        guard let error else { return false }
        guard error != .userCancelled else { return false }
        guard case .restoreFailed = error else { return true }
        return false
    }
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    public var body: some View {
        ZStack {
            let info = showError(error: store.storeError)
            if showError(error: store.storeError) == true {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = store.storeError {
                        Text(error.description(locale: locale))
                            .fontWeight(.thin)
                            .foregroundStyle(Color.red)
                    }
                }
                .lineLimit(nil)  // 允许多行显示
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    content()
                }
                .overlay {
                    Group {
                        if store.isLoading == true {
                            VStack {
                                ProgressView().controlSize(.small)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.background.opacity(0.73))
                        }
                    }
                }
            }
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
