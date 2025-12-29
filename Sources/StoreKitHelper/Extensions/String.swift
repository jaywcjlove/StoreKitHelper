//
//  String.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import SwiftUI

internal extension String {
    static func localizedString(key: String, locale: Locale, _ arguments: any CVarArg...) -> String {
        guard let path = Bundle.module.path(forResource: locale.identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            let format = NSLocalizedString(key, bundle: .module, comment: "")
            return String.localizedStringWithFormat(format, arguments)
        }
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String.localizedStringWithFormat(format, arguments)
    }
}
