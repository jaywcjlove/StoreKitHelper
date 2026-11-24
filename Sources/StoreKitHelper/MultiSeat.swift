import Foundation
import StoreKit

/// 多名额订阅（Multi-seat Purchases）的购买上限和订阅管理入口。
///
/// 团购一次最多 100 个席位，其中包含购买者自己的那一席。
/// 减少席位不能走购买接口，只能到订阅设置里改，下次续期才生效。
public enum MultiSeatPurchase {
    public static let maximumSeatCount = 100
    /// 系统订阅管理页。席位减少、以及还不能展示邀请面板时的邀请，都从这里走。
    public static let subscriptionSettingsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// 每个席位同一个价格。最后一档没有上限。
    public static func perSeatTier(pricePerSeat: Decimal) -> MultiSeatPriceTier {
        MultiSeatPriceTier(minimumSeats: 1, maximumSeats: nil, pricePerSeat: pricePerSeat)
    }

    /// 按档计算团购总价。席位从最贵的一档开始填。
    ///
    /// 例如 1–5 席每位 9.99、6–10 席每位 7.99，买 8 席是 5 × 9.99 + 3 × 7.99 = 73.92。
    /// StoreKit 没有提供这个合计。
    public static func quote(
        seatCount: Int,
        tiers: [MultiSeatPriceTier]
    ) -> Result<MultiSeatQuote, MultiSeatQuoteError> {
        quoteMultiSeatPurchase(seatCount: seatCount, tiers: tiers)
    }
}

/// 产品上的一档席位价格。`maximumSeats == nil` 表示从 `minimumSeats` 起不再封顶。
public struct MultiSeatPriceTier: Hashable, Sendable {
    public var minimumSeats: Int
    public var maximumSeats: Int?
    public var pricePerSeat: Decimal

    public init(minimumSeats: Int, maximumSeats: Int?, pricePerSeat: Decimal) {
        self.minimumSeats = minimumSeats
        self.maximumSeats = maximumSeats
        self.pricePerSeat = pricePerSeat
    }

    func contains(seat: Int) -> Bool {
        guard seat >= minimumSeats else { return false }
        guard let maximumSeats else { return true }
        return seat <= maximumSeats
    }
}

public struct MultiSeatQuoteLine: Hashable, Sendable {
    public var tier: MultiSeatPriceTier
    public var seatCount: Int
    public var subtotal: Decimal

    public init(tier: MultiSeatPriceTier, seatCount: Int, subtotal: Decimal) {
        self.tier = tier
        self.seatCount = seatCount
        self.subtotal = subtotal
    }
}

public struct MultiSeatQuote: Hashable, Sendable {
    public var seatCount: Int
    public var total: Decimal
    public var lines: [MultiSeatQuoteLine]

    public init(seatCount: Int, total: Decimal, lines: [MultiSeatQuoteLine]) {
        self.seatCount = seatCount
        self.total = total
        self.lines = lines
    }
}

public enum MultiSeatQuoteError: Error, Equatable, Sendable {
    case invalidSeatCount
    case exceedsGroupLimit
    case emptyTiers
    case invalidTier
    case uncoveredSeat
    case overlappingTier
}

/// 交易里已经买下的一档席位，不是产品目录上的价格区间。
public struct MultiSeatPaidTier: Hashable, Sendable {
    public var pricePerSeat: Decimal
    public var seatCount: Int

    public init(pricePerSeat: Decimal, seatCount: Int) {
        self.pricePerSeat = pricePerSeat
        self.seatCount = seatCount
    }
}

/// 当前 Apple 账号上，某个多名额订阅还有效的席位。
///
/// 访问权看这笔交易自己，不看团购购买者的交易。
/// 开发者托管邀请的成员没有 App Store 交易，不会出现在这里。
public struct MultiSeatGrant: Hashable, Sendable {
    public var productID: String
    /// 扣掉已退款席位后，这组交易覆盖的席位数。加席会产生多笔交易，这里是它们的合计。
    public var activeSeatCount: Int
    public var revokedSeatCount: Int
    public var originalTransactionID: UInt64
    public var ownership: MultiSeatOwnership
    public var invitationManagement: MultiSeatInvitationManagement?
    /// 各笔交易上报的标价档。加席那笔交易的标价是完整单价，不是按剩余天数折算后的实付。
    public var paidTiers: [MultiSeatPaidTier]
    /// 下次续期的席位数。续期信息还没带这个字段时为 nil。
    public var renewalSeatCount: Int?

    public init(
        productID: String,
        activeSeatCount: Int,
        revokedSeatCount: Int,
        originalTransactionID: UInt64,
        ownership: MultiSeatOwnership,
        invitationManagement: MultiSeatInvitationManagement?,
        paidTiers: [MultiSeatPaidTier],
        renewalSeatCount: Int?
    ) {
        self.productID = productID
        self.activeSeatCount = activeSeatCount
        self.revokedSeatCount = revokedSeatCount
        self.originalTransactionID = originalTransactionID
        self.ownership = ownership
        self.invitationManagement = invitationManagement
        self.paidTiers = paidTiers
        self.renewalSeatCount = renewalSeatCount
    }

    /// 各档标价乘席位数的合计。不要把它当成加席时的实付金额。
    public var listedSeatTotal: Decimal {
        paidTiers.reduce(0) { partial, tier in
            partial + tier.pricePerSeat * Decimal(tier.seatCount)
        }
    }
}

public enum MultiSeatOwnership: Hashable, Sendable {
    /// 团购购买者，自己付款。
    case purchased
    /// 受邀成员，或机构分配到席位的人。
    case assigned
    /// 只有团购购买者可以把自己的这一席分享给家人。
    case familyShared
    case unknown(String)
}

public enum MultiSeatInvitationManagement: Hashable, Sendable {
    case apple
    case developer
    case unknown(String)
}

extension Product {
    /// 用产品自己的货币格式显示多名额总价。档位盖不住席位数时返回 nil。
    public func formattedMultiSeatTotal(seatCount: Int, tiers: [MultiSeatPriceTier]) -> String? {
        guard case .success(let quote) = MultiSeatPurchase.quote(seatCount: seatCount, tiers: tiers) else {
            return nil
        }
        return quote.total.formatted(priceFormatStyle)
    }
}

func quoteMultiSeatPurchase(
    seatCount: Int,
    tiers: [MultiSeatPriceTier]
) -> Result<MultiSeatQuote, MultiSeatQuoteError> {
    guard seatCount >= 1 else { return .failure(.invalidSeatCount) }
    guard seatCount <= MultiSeatPurchase.maximumSeatCount else { return .failure(.exceedsGroupLimit) }
    guard tiers.isEmpty == false else { return .failure(.emptyTiers) }
    for tier in tiers {
        if tier.minimumSeats < 1 { return .failure(.invalidTier) }
        if let maximumSeats = tier.maximumSeats, maximumSeats < tier.minimumSeats {
            return .failure(.invalidTier)
        }
    }

    var lines: [MultiSeatQuoteLine] = []
    for seat in 1...seatCount {
        let matches = tiers.filter { $0.contains(seat: seat) }
        if matches.isEmpty { return .failure(.uncoveredSeat) }
        if matches.count > 1 { return .failure(.overlappingTier) }
        let tier = matches[0]
        if let index = lines.indices.last, lines[index].tier == tier {
            lines[index].seatCount += 1
            lines[index].subtotal += tier.pricePerSeat
        } else {
            lines.append(MultiSeatQuoteLine(tier: tier, seatCount: 1, subtotal: tier.pricePerSeat))
        }
    }
    let total = lines.reduce(Decimal(0)) { $0 + $1.subtotal }
    return .success(MultiSeatQuote(seatCount: seatCount, total: total, lines: lines))
}

enum MultiSeatPurchaseValidation: Equatable {
    case valid
    case invalidSeatCount
    case seatReductionNotAllowed
}

/// `purchaserActiveSeats` 只传团购购买者自己名下的席位。受邀成员没有可减少的购买。
func validateMultiSeatPurchase(
    targetSeatQuantity: Int,
    purchaserActiveSeats: Int?
) -> MultiSeatPurchaseValidation {
    guard targetSeatQuantity >= 1, targetSeatQuantity <= MultiSeatPurchase.maximumSeatCount else {
        return .invalidSeatCount
    }
    if let purchaserActiveSeats, targetSeatQuantity < purchaserActiveSeats {
        return .seatReductionNotAllowed
    }
    return .valid
}

struct SeatTransactionFact: Equatable {
    var transactionID: UInt64
    var productID: String
    var purchasedQuantity: Int
    var revokedSeatQuantity: Int
    var originalID: UInt64
    var ownership: MultiSeatOwnership
    var invitationManagement: MultiSeatInvitationManagement?
    var paidTiers: [MultiSeatPaidTier]
    var renewalSeatCount: Int?
}

struct ParsedMultiSeatInfo: Equatable {
    var invitationManagement: MultiSeatInvitationManagement?
    var revokedSeatQuantity: Int
    var paidTiers: [MultiSeatPaidTier]
}

struct MultiSeatRefreshInput: Equatable {
    var scannedFacts: [SeatTransactionFact] = []
    var sessionFacts: [SeatTransactionFact] = []
    var purchasedProductIDs: Set<String> = []
    /// 这次刷新读到了交易的产品。没读到时保留上一份席位，避免空缓存把刚买的席位清掉。
    var productsSeenInEntitlements: Set<String> = []
    var previousGrants: [String: MultiSeatGrant] = [:]
}

struct MultiSeatRefreshOutput: Equatable {
    var grants: [String: MultiSeatGrant]
    var sessionFacts: [SeatTransactionFact]
}

func multiSeatOwnership(for ownershipType: StoreKit.Transaction.OwnershipType) -> MultiSeatOwnership {
    if ownershipType == .purchased { return .purchased }
    if ownershipType == .familyShared { return .familyShared }
    if ownershipType == .assigned { return .assigned }
    return .unknown(ownershipType.rawValue)
}

func multiSeatInvitationManagement(for rawValue: String) -> MultiSeatInvitationManagement {
    switch rawValue {
    case "APPLE":
        return .apple
    case "DEVELOPER":
        return .developer
    default:
        return .unknown(rawValue)
    }
}

/// 交易 JSON 是签名载荷。`multiSeatInfo` 不在字段里就不是多名额交易。
/// 价格按 App Store 的毫单位换算成货币金额。
func parseMultiSeatInfo(from jsonRepresentation: Data) -> ParsedMultiSeatInfo? {
    guard let payload = try? JSONDecoder().decode(TransactionSeatPayload.self, from: jsonRepresentation),
          let info = payload.multiSeatInfo else {
        return nil
    }
    let tiers = (info.priceTiers ?? []).compactMap { tier -> MultiSeatPaidTier? in
        guard let price = tier.price, let quantity = tier.quantity, quantity > 0 else { return nil }
        return MultiSeatPaidTier(pricePerSeat: price.currencyAmount, seatCount: quantity)
    }
    return ParsedMultiSeatInfo(
        invitationManagement: info.invitationManagement.map(multiSeatInvitationManagement),
        revokedSeatQuantity: max(0, info.revokedSeatQuantity ?? 0),
        paidTiers: tiers
    )
}

func parseRenewalSeatCount(from jsonRepresentation: Data) -> Int? {
    guard let payload = try? JSONDecoder().decode(RenewalSeatPayload.self, from: jsonRepresentation),
          let renewalQuantity = payload.renewalQuantity,
          renewalQuantity >= 0 else {
        return nil
    }
    return renewalQuantity
}

func makeSeatTransactionFact(
    transactionID: UInt64,
    productID: String,
    purchasedQuantity: Int,
    originalID: UInt64,
    ownership: MultiSeatOwnership,
    jsonRepresentation: Data,
    renewalSeatCount: Int?
) -> SeatTransactionFact? {
    guard let info = parseMultiSeatInfo(from: jsonRepresentation) else { return nil }
    return SeatTransactionFact(
        transactionID: transactionID,
        productID: productID,
        purchasedQuantity: purchasedQuantity,
        revokedSeatQuantity: info.revokedSeatQuantity,
        originalID: originalID,
        ownership: ownership,
        invitationManagement: info.invitationManagement,
        paidTiers: info.paidTiers,
        renewalSeatCount: renewalSeatCount
    )
}

func combineMultiSeatGrants(facts: [SeatTransactionFact]) -> [String: MultiSeatGrant] {
    var unique: [SeatTransactionFact] = []
    var seenTransactionIDs: Set<UInt64> = []
    for fact in facts where seenTransactionIDs.insert(fact.transactionID).inserted {
        unique.append(fact)
    }

    let grouped = Dictionary(grouping: unique, by: \.productID)
    var grants: [String: MultiSeatGrant] = [:]
    for (productID, group) in grouped {
        guard let preferred = group.first(where: { $0.ownership == .purchased }) ?? group.first else {
            continue
        }
        var quantities: [Decimal: Int] = [:]
        for fact in group {
            for tier in fact.paidTiers where tier.seatCount > 0 {
                quantities[tier.pricePerSeat, default: 0] += tier.seatCount
            }
        }
        let paidTiers = quantities
            .map { MultiSeatPaidTier(pricePerSeat: $0.key, seatCount: $0.value) }
            .sorted { $0.pricePerSeat > $1.pricePerSeat }
        let invitation = preferred.invitationManagement
            ?? group.compactMap(\.invitationManagement).first
        let renewal = preferred.renewalSeatCount
            ?? group.compactMap(\.renewalSeatCount).first
        let ownership: MultiSeatOwnership
        if group.contains(where: { $0.ownership == .purchased }) {
            ownership = .purchased
        } else if group.contains(where: { $0.ownership == .assigned }) {
            ownership = .assigned
        } else if group.contains(where: { $0.ownership == .familyShared }) {
            ownership = .familyShared
        } else {
            ownership = preferred.ownership
        }
        grants[productID] = MultiSeatGrant(
            productID: productID,
            activeSeatCount: group.reduce(0) { $0 + max(0, $1.purchasedQuantity - $1.revokedSeatQuantity) },
            revokedSeatCount: group.reduce(0) { $0 + max(0, $1.revokedSeatQuantity) },
            originalTransactionID: preferred.originalID,
            ownership: ownership,
            invitationManagement: invitation,
            paidTiers: paidTiers,
            renewalSeatCount: renewal
        )
    }
    return grants
}

func mergeMultiSeatGrants(_ input: MultiSeatRefreshInput) -> MultiSeatRefreshOutput {
    let scannedTransactionIDs = Set(input.scannedFacts.map(\.transactionID))
    let remainingSessionFacts = input.sessionFacts.filter { scannedTransactionIDs.contains($0.transactionID) == false }
    let usableSessionFacts = remainingSessionFacts.filter { input.purchasedProductIDs.contains($0.productID) }
    let scanned = input.scannedFacts.filter { input.purchasedProductIDs.contains($0.productID) }
    var grants = combineMultiSeatGrants(facts: scanned + usableSessionFacts)
    for productID in input.purchasedProductIDs where grants[productID] == nil {
        guard input.productsSeenInEntitlements.contains(productID) == false,
              let previous = input.previousGrants[productID] else {
            continue
        }
        grants[productID] = previous
    }
    return MultiSeatRefreshOutput(
        grants: grants,
        sessionFacts: remainingSessionFacts.filter { input.purchasedProductIDs.contains($0.productID) }
    )
}

private struct TransactionSeatPayload: Decodable {
    var multiSeatInfo: SeatInfoPayload?
}

private struct SeatInfoPayload: Decodable {
    var invitationManagement: String?
    var revokedSeatQuantity: Int?
    var priceTiers: [SeatTierPayload]?
}

private struct SeatTierPayload: Decodable {
    var price: SeatPrice?
    var quantity: Int?
}

private struct RenewalSeatPayload: Decodable {
    var renewalQuantity: Int?
}

/// 签名载荷里的价格是毫单位整数。带小数时按货币金额使用。
private struct SeatPrice: Decodable {
    var currencyAmount: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let milliunits = try? container.decode(Int.self) {
            currencyAmount = Decimal(milliunits) / Decimal(1000)
            return
        }
        currencyAmount = try container.decode(Decimal.self)
    }
}
