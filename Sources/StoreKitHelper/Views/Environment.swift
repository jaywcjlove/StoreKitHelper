//
//  EnvironmentEvents.swift
//  StoreKitHelper
//
//  Created by 王楚江 on 2025/3/4.
//


import SwiftUI

struct TermsOfServiceHandle: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: (() -> Void)? = nil
}
struct TermsOfServiceLabel: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: String = ""
}
struct PrivacyPolicyHandle: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: (() -> Void)? = nil
}
struct PrivacyPolicyLabel: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: String = ""
}
struct PricingContent: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue: PricingContentType? = nil
}

public typealias PricingContentType = () -> AnyView

extension EnvironmentValues {
    var termsOfServiceLabel: String {
        get { self[TermsOfServiceLabel.self] }
        set { self[TermsOfServiceLabel.self] = newValue }
    }
    var termsOfServiceHandle: (() -> Void)? {
        get { self[TermsOfServiceHandle.self] }
        set { self[TermsOfServiceHandle.self] = newValue }
    }
    var privacyPolicyLabel: String {
        get { self[PrivacyPolicyLabel.self] }
        set { self[PrivacyPolicyLabel.self] = newValue }
    }
    var privacyPolicyHandle: (() -> Void)? {
        get { self[PrivacyPolicyHandle.self] }
        set { self[PrivacyPolicyHandle.self] = newValue }
    }
    var pricingContent: PricingContentType? {
        get { self[PricingContent.self] }
        set { self[PricingContent.self] = newValue }
    }
}

// MARK: - View Extensions
public extension View {
    func termsOfService(action: @escaping () -> Void) -> some View {
        return self.environment(\.termsOfServiceHandle, action)
    }
    func termsOfService(label: String, action: @escaping () -> Void) -> some View {
        return self.environment(\.termsOfServiceLabel, label)
                .environment(\.termsOfServiceHandle, action)
    }
    func privacyPolicy(action: @escaping () -> Void) -> some View {
        return self.environment(\.privacyPolicyHandle, action)
    }
    func privacyPolicy(label: String, action: @escaping () -> Void) -> some View {
        return self.environment(\.privacyPolicyLabel, label)
                .environment(\.privacyPolicyHandle, action)
    }
    /// 定价说明
    func pricingContent(action: PricingContentType? = nil) -> some View {
        return self.environment(\.pricingContent, action)
    }
}
