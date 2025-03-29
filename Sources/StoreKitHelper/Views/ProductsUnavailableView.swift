//
//  ProductsUnavailableView.swift
//  StoreKitHelper
//
//  Created by wong on 3/28/25.
//

import SwiftUI

public struct ProductsUnavailableView: View {
    @Environment(\.locale) var locale
    public init() {}
    public var body: some View {
        VStack(spacing: 6) {
            Text("store_unavailable".localized(locale: locale)).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 6) {
                if #available(iOS 17.0, *) {
                    Text("no_in_app_purchases".localized(locale: locale))
                        .foregroundStyle(Color.secondary).fontWeight(.thin)
                } else {
                    Text("no_in_app_purchases".localized(locale: locale))
                        .fontWeight(.thin)
                }
                Text(.init("network_connection_check".localized(locale: locale)))
                    .foregroundStyle(Color.yellow).fontWeight(.thin)
                    .environment(\.openURL, OpenURLAction { url in
                        restartApp()
                        return .handled
                    })
            }
        }
        .lineLimit(nil)  // 允许多行显示
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }
}
