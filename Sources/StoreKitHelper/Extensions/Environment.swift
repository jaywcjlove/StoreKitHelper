//
//  Environment.swift
//  StoreKitHelper
//
//  Created by wong on 12/29/25.
//

import SwiftUI

public extension EnvironmentValues {
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
    
    /// 弹出框，关闭函数
    var popupDismissHandle: (() -> Void)? {
        get { self[PopupDismissHandle.self] }
        set { self[PopupDismissHandle.self] = newValue }
    }
    
    /// 定价说明内容
    /// 付费说明内容 - 定价说明
    var pricingContent: (() -> AnyView)? {
        get { self[PricingContent.self] }
        set { self[PricingContent.self] = newValue }
    }
}

struct PopupDismissHandle: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: (() -> Void)? = nil
}

// 定义一个环境键，泛型视图类型
struct PricingContent<T: View>: EnvironmentKey {
    // 使用计算属性来提供默认值
    static var defaultValue: (() -> T)? {
        return nil  // 可以返回一个默认的视图构造方法
    }
}

struct TermsOfServiceHandle: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: (() -> Void)? = nil
}
struct TermsOfServiceLabel: EnvironmentKey {
    static let defaultValue: String = ""
}
struct PrivacyPolicyHandle: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: (() -> Void)? = nil
}
struct PrivacyPolicyLabel: EnvironmentKey {
    static let defaultValue: String = ""
}
