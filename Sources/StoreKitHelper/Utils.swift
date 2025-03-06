//
//  Untitled.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/5.
//

import AppKit

public class Utils {
    nonisolated(unsafe) static let shared = Utils()
    @MainActor public static func alert(title: String, message: String) {
        // 路径不存在时弹出警告提示框
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.window.level = .mainMenu
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
