import Foundation

public enum AlertKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case newBuy, actionChanged, priceAbove, priceBelow
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .newBuy: "Новая рекомендация покупать"
        case .actionChanged: "Изменение рекомендации"
        case .priceAbove: "Цена пересекла уровень вверх"
        case .priceBelow: "Цена пересекла уровень вниз"
        }
    }
    public var needsThreshold: Bool { self == .priceAbove || self == .priceBelow }
}

public struct AlertRule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let ticker: String
    public let kind: AlertKind
    public let threshold: Double?
    public init(id: UUID = UUID(), ticker: String, kind: AlertKind, threshold: Double? = nil) {
        self.id = id
        self.ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.kind = kind
        self.threshold = threshold
    }
    public var isValid: Bool {
        !ticker.isEmpty && (kind.needsThreshold ? threshold.map { $0.isFinite && $0 > 0 } == true : threshold == nil)
    }
}

public struct AlertNotification: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let ruleID: UUID
    public let ticker: String
    public let message: String
    public let createdAt: Date
}

public enum AlertEngine {
    /// Only transitions between two fresh, publishable snapshots generate an in-app alert.
    /// Initial loads, offline demo, provider failures and degraded feeds never create a buy alert.
    public static func evaluate(rules: [AlertRule], previous: MarketSnapshot, current: MarketSnapshot,
                                at now: Date) -> [AlertNotification] {
        guard previous.source.blockingIssues(at: now).isEmpty,
              current.source.blockingIssues(at: now).isEmpty,
              current.source.updatedAt > previous.source.updatedAt else { return [] }
        return rules.filter(\.isValid).compactMap { rule in
            guard let before = previous.stock(ticker: rule.ticker), let after = current.stock(ticker: rule.ticker) else { return nil }
            let triggered: Bool
            switch rule.kind {
            case .newBuy: triggered = before.signal.action != .buy && after.signal.action == .buy
            case .actionChanged: triggered = before.signal.action != after.signal.action
            case .priceAbove: triggered = before.price < rule.threshold! && after.price >= rule.threshold!
            case .priceBelow: triggered = before.price > rule.threshold! && after.price <= rule.threshold!
            }
            guard triggered else { return nil }
            let thresholdLabel = rule.threshold?.formatted(.currency(code: "USD")) ?? "—"
            let detail = rule.kind.needsThreshold
                ? "\(after.price.formatted(.currency(code: "USD"))) (уровень \(thresholdLabel))"
                : "\(before.signal.action.title) → \(after.signal.action.title)"
            return AlertNotification(id: "\(rule.id.uuidString)-\(current.source.updatedAt.timeIntervalSince1970)",
                ruleID: rule.id, ticker: rule.ticker, message: "\(rule.kind.title): \(detail)", createdAt: current.source.updatedAt)
        }
    }
}