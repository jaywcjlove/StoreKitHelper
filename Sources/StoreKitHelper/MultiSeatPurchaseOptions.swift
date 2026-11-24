import StoreKit

/// `Product.PurchaseOption.seats(_:)` 从 Xcode 27.3 的 SDK 才有声明，并且会回部署到更早的系统。
/// 这里用协议见证接上它：SDK 里有这个方法时，购买走 StoreKit；没有时见证落回下面的占位选项，调用方据此放弃购买。
/// 不能改走 `quantity(_:)`，那个选项的上限是 10，而且不表示购买完成后的席位总数。
protocol MultiSeatPurchaseOptionBuilding {
    static func seats(_ targetSeatQuantity: Int) -> Self
    static func multiSeatInvitationSheetSuppressed(_ isSuppressed: Bool) -> Self
}

enum MultiSeatPurchaseOptionKey {
    static let unavailable = "storeKitHelper.multiSeat.sdkUnavailable"
}

extension MultiSeatPurchaseOptionBuilding {
    static func seats(_ targetSeatQuantity: Int) -> Self {
        _ = targetSeatQuantity
        return unavailablePurchaseOption(value: "seats")
    }

    static func multiSeatInvitationSheetSuppressed(_ isSuppressed: Bool) -> Self {
        _ = isSuppressed
        return unavailablePurchaseOption(value: "sheet")
    }

    private static func unavailablePurchaseOption(value: String) -> Self {
        let option = Product.PurchaseOption.custom(key: MultiSeatPurchaseOptionKey.unavailable, value: value)
        guard let typed = option as? Self else {
            fatalError("Multi-seat purchase options are unavailable")
        }
        return typed
    }
}

extension Product.PurchaseOption: MultiSeatPurchaseOptionBuilding {}

func resolvedMultiSeatPurchaseOptions(
    seats targetSeatQuantity: Int,
    suppressInvitationSheet: Bool
) -> Set<Product.PurchaseOption>? {
    let seatsOption = seatPurchaseOption(Product.PurchaseOption.self, targetSeatQuantity)
    let seatSentinel = Product.PurchaseOption.custom(key: MultiSeatPurchaseOptionKey.unavailable, value: "seats")
    guard seatsOption != seatSentinel else { return nil }

    var options: Set<Product.PurchaseOption> = [seatsOption]
    guard suppressInvitationSheet else { return options }

    let suppressOption = invitationSuppressionOption(Product.PurchaseOption.self)
    let sheetSentinel = Product.PurchaseOption.custom(key: MultiSeatPurchaseOptionKey.unavailable, value: "sheet")
    guard suppressOption != sheetSentinel else { return nil }
    options.insert(suppressOption)
    return options
}

/// 泛型见证：SDK 提供 `seats(_:)` 时用它，否则用上面的占位实现。
private func seatPurchaseOption<T: MultiSeatPurchaseOptionBuilding>(
    _ type: T.Type,
    _ targetSeatQuantity: Int
) -> T {
    T.seats(targetSeatQuantity)
}

private func invitationSuppressionOption<T: MultiSeatPurchaseOptionBuilding>(_ type: T.Type) -> T {
    T.multiSeatInvitationSheetSuppressed(true)
}
