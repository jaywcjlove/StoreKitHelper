//
//  String.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import SwiftUI

public enum StoreKitHelperL18n {
    public static func localized(key: String, locale: Locale, _ arguments: any CVarArg...) -> String {
        String.localizedString(key: key, locale: locale, arguments)
    }
}

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
