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
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
