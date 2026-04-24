//
//  Notify.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//


#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

class NotifyAlert {
    nonisolated(unsafe) static let shared = NotifyAlert()
    @MainActor static func alert(title: String, message: String, locale: Locale = .current) {
        let okTitle = StoreKitHelperL18n.localized(key: "ok", locale: locale)
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.window.level = .mainMenu
        alert.addButton(withTitle: okTitle)
        alert.runModal()
        #else
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return
        }
        var topViewController = keyWindow.rootViewController
        while let presentedViewController = topViewController?.presentedViewController {
            topViewController = presentedViewController
        }
        guard let viewController = topViewController else {
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: okTitle, style: .default))
        viewController.present(alert, animated: true)
        #endif
    }
}
