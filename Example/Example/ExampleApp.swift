//
//  ExampleApp.swift
//  Example
//
//  Created by wong on 12/28/25.
//

import SwiftUI
import StoreKitHelper

enum AppProduct: String, InAppProduct {
    case lifetime = "test.lifetime"
    case monthly = "test.monthly"
    var id: String { rawValue }
}

@main
struct ExampleApp: App {
    @StateObject var store = StoreContext(products: AppProduct.allCases)
    @AppStorage("colorScheme") private var colorSchemeNumber = 0
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(colorScheme)
        }
    }
    var colorScheme: ColorScheme? {
        var result: ColorScheme? = .none
        switch colorSchemeNumber {
        case 0: result = .none
        case 1: result = .dark
        case 2: result = .light
        default:
            result = .none
        }
        return result
    }
}
