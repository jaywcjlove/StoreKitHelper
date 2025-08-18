//
//  String.swift
//  StoreKitHelper
//
//  Created by Wang Chujiang on 2025/3/5.
//

import Foundation

public extension String {
    func localized() -> String {
        return NSLocalizedString(self, bundle: .module, comment: "")
    }
    func localized(locale: Locale = Locale.current) -> String {
        localized(locale: locale, arguments: [])
    }
    func localized(arguments: any CVarArg...) -> String {
        return String(format: NSLocalizedString(self, bundle: .module, comment: ""), arguments)
    }
}

internal extension String {
    func localized(locale: Locale = Locale.current, arguments: any CVarArg...) -> String {
        // Get language and region codes
        let languageCode = locale.language.languageCode?.identifier ?? ""
        let regionCode = locale.region?.identifier ?? ""
        
        // Map region code to corresponding language
        var targetLanguage = languageCode
        
        // Region code to language mapping
        let regionToLanguageMap: [String: String] = [
            // Chinese regions
            "CN": "zh-Hans",    // Mainland China -> Simplified Chinese
            "SG": "zh-Hans",    // Singapore -> Simplified Chinese
            "TW": "zh-Hant",    // Taiwan -> Traditional Chinese
            "HK": "zh-Hant",    // Hong Kong -> Traditional Chinese
            "MO": "zh-Hant",    // Macau -> Traditional Chinese
            
            // Other language regions
            "JP": "ja",         // Japan -> Japanese
            "KR": "ko",         // South Korea -> Korean
            "DE": "de",         // Germany -> German
            "AT": "de",         // Austria -> German
            "CH": "de",         // Switzerland -> German (partial regions)
            "FR": "fr",         // France -> French
            "BE": "fr",         // Belgium -> French (partial regions)
            "CA": "fr",         // Canada -> French (partial regions)
        ]
        
        // First check region mapping
        if let mappedLanguage = regionToLanguageMap[regionCode] {
            targetLanguage = mappedLanguage
        } else if languageCode == "zh" {
            // If language is Chinese but region has no mapping, default to Simplified Chinese
            targetLanguage = "zh-Hans"
        }
        
        // Try to find localization files, search by priority:
        // 1. Region-mapped language (e.g., zh-Hans, zh-Hant)
        // 2. Original language code (e.g., en, fr, de, etc.)
        // 3. English as fallback
        var path = Bundle.module.path(forResource: targetLanguage, ofType: "lproj")
        
        if path == nil && targetLanguage != languageCode {
            path = Bundle.module.path(forResource: languageCode, ofType: "lproj")
        }
        
        if path == nil && targetLanguage != "en" && languageCode != "en" {
            path = Bundle.module.path(forResource: "en", ofType: "lproj")
        }
        
        guard let validPath = path else {
            return NSLocalizedString(self, tableName: nil, bundle: Bundle.module, comment: "")
        }
        
        let languageBundle = Bundle(path: validPath)
        let localizedString = NSLocalizedString(self, tableName: nil, bundle: languageBundle ?? Bundle.module, comment: "")
        
        if arguments.count > 0 {
            return String(format: localizedString, arguments)
        }
        return localizedString
    }
}
