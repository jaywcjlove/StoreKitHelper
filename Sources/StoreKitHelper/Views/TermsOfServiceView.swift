//
//  TermsOfService.swift
//  StoreKitHelper
//
//  Created by wong on 3/28/25.
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
                        let text = termsOfServiceLabel.isEmpty == true ? "terms_of_service".localized(locale: locale) : termsOfServiceLabel
                        Text(text).frame(maxWidth: .infinity)
                    })
                    .glassEffectButton()
                }
                if let action = privacyPolicyHandle {
                    Button(action: action, label: {
                        let text = privacyPolicyLabel.isEmpty == true ? "privacy_policy".localized(locale: locale) : privacyPolicyLabel
                        Text(text).frame(maxWidth: .infinity)
                    })
                    .glassEffectButton()
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TermsOfServiceView()
            .termsOfService() {
            }
            .privacyPolicy() {
            }
            .padding(.top, 0)
            .padding(.bottom, 8)
    }
    .frame(width: 560)
}
