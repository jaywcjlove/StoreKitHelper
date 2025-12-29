//
//  TermsOfServiceView.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//


import SwiftUI

// MARK: 服务条款 & 隐私政策
struct TermsOfServiceView: View {
    @Environment(\.termsOfServiceHandle) private var termsOfServiceHandle
    @Environment(\.privacyPolicyHandle) private var privacyPolicyHandle
    
    @Environment(\.termsOfServiceLabel) private var termsOfServiceLabel
    @Environment(\.privacyPolicyLabel) private var privacyPolicyLabel
    @Environment(\.locale) var locale
    var body: some View {
        if termsOfServiceHandle != nil || privacyPolicyHandle != nil {
            Divider()
            HStack {
                if let action = termsOfServiceHandle {
                    Button(action: action, label: {
                        Text(termsOfServiceLabel.isEmpty ? "terms_of_service" : LocalizedStringKey(termsOfServiceLabel), bundle: .module)
                            .frame(maxWidth: .infinity)
                            
                    })
#if os(macOS)
                    .buttonStyle(.link)
#elseif os(iOS)
                    .glassEffectButton()
#endif
                }
                if let action = privacyPolicyHandle {
                    Button(action: action, label: {
                        Text(privacyPolicyLabel.isEmpty ? "privacy_policy" : LocalizedStringKey(privacyPolicyLabel), bundle: .module)
                            .frame(maxWidth: .infinity)
                    })
#if os(macOS)
                    .buttonStyle(.link)
#elseif os(iOS)
                    .glassEffectButton()
#endif
                }
            }
            .padding(.horizontal, 8)
            .environment(\.locale, locale)
        }
    }
}


func localeBundle(locale: Locale) -> Bundle {
    return LocalizedStringKey.getBundle(locale: locale)
}

extension LocalizedStringKey {
    func localizedString(locale: Locale) -> String {
        let mirror = Mirror(reflecting: self)
        let key = mirror.children.first { $0.label == "key" }?.value as? String ?? ""
        let languageCode = locale.identifier
        let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") ?? ""
        let bundle = Bundle(path: path) ?? .main
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
    static func getBundle(locale: Locale) -> Bundle {
        let languageCode = locale.identifier
        let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") ?? ""
        return path.isEmpty ? .main : Bundle(path: path)!
    }
}


#Preview {
    VStack(spacing: 0) {
        TermsOfServiceView()
            .environment(\.termsOfServiceHandle, {
                // Action triggered when the [Terms of Service] button is clicked
                print("Action triggered when the [Terms of Service] button is clicked")
            })
            .environment(\.privacyPolicyHandle, {
                // Action triggered when the [Privacy Policy] button is clicked
                print("Action triggered when the [Privacy Policy] button is clicked")
            })
            .padding(.top, 0)
            .padding(.bottom, 8)
    }
    .frame(width: 560)
}
