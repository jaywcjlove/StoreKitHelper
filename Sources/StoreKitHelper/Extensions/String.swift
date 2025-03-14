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
    func localized(locale: Locale = Locale.current) -> String {
        // 获取语言代码（例如 "en_US", "fr_FR"）
        let languageCode = locale.identifier
        
        // 获取指定语言的 bundle 路径
        guard let path = Bundle.module.path(forResource: languageCode, ofType: "lproj") else {
            return NSLocalizedString(self, tableName: nil, bundle: Bundle.module, value: "", comment: "")
        }
        
        // 使用获取到的路径创建一个新的 Bundle
        let languageBundle = Bundle(path: path)
        
        // 使用新的 bundle 来加载本地化字符串
        return NSLocalizedString(self, tableName: nil, bundle: languageBundle ?? Bundle.module, value: "", comment: "")
    }
}
