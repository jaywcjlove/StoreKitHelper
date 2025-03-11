//
//  extensions.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/5.
//

import Foundation

public extension String {
    func localized() -> String {
        return NSLocalizedString(self, bundle: .module, comment: "")
    }
}
