//
//  UIApplication.swift
//  StoreKitHelper
//
//  Created by wong on 12/31/25.
//

#if canImport(UIKit)
import UIKit

extension UIApplication {
    static func applicationIconImage() -> UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primary["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }
        return UIImage(named: iconName)
    }
}
#endif
